"""
=============================================================================
FILE: ml-serving/05-custom-fastapi-serving/runtime-image/app/main.py
PURPOSE: FastAPI inference server — the production ML serving layer.

ENTERPRISE ARCHITECTURE POSITION:
  This service sits at the center of the ML serving stack:

    External Traffic
         ↓
    [Ingress Controller / ALB]    ← Routes /api/v1/predict to this service
         ↓
    [Service: ml-inference-svc]   ← Load balances across replicas
         ↓
    [Pod 1]  [Pod 2]  [Pod 3]     ← Replicas managed by Deployment
    [FastAPI] [FastAPI] [FastAPI]  ← This file, 3 instances
         ↓
    [Prometheus]                  ← Scrapes /metrics from all pods
         ↓
    [KEDA / HPA]                  ← Scales Deployment based on metrics

DESIGN DECISIONS:
  - async endpoints: FastAPI's async allows concurrent request handling without
    blocking the event loop on I/O. For CPU-bound inference, use asyncio.to_thread()
    to run prediction in a thread pool (doesn't block the event loop).

  - Lifespan context manager: The new (Starlette 0.20+, FastAPI 0.93+) way to
    run startup/shutdown logic. Replaces deprecated @app.on_event("startup").
    Enterprise pattern: initializes DB connections, loads models, warms caches.

  - /metrics: Prometheus format. This is what KEDA reads to make scaling decisions.
    The inference_latency_seconds histogram drives P95 latency-based autoscaling.

  - Versioned API: /api/v1/predict — version prefix allows breaking changes
    without breaking existing clients (deploy v2 alongside v1, migrate gradually).
=============================================================================
"""

import asyncio
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, JSONResponse
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from .model_loader import ModelLoader
from .schemas import (
    WineFeatures,
    PredictionResponse,
    BatchPredictionRequest,
    BatchPredictionResponse,
    HealthResponse,
    ReadinessResponse,
    ModelInfoResponse,
)

# ─── LOGGING ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s"
)
logger = logging.getLogger("ml_inference_server")

# ─── GLOBAL MODEL LOADER ──────────────────────────────────────────────────────
# Module-level singleton. FastAPI workers share this object within a single
# process. Uvicorn workers (different processes) each load their own model.
# That's expected — each pod/worker has its own in-memory model copy.
model_loader = ModelLoader()

# ─── APPLICATION VERSION ──────────────────────────────────────────────────────
# Injected from ConfigMap via environment variable (see 01-application-config.yaml)
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
APP_NAME = os.getenv("APP_NAME", "wine-quality-inference-server")


# ─── LIFESPAN: STARTUP + SHUTDOWN LOGIC ───────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Manages the application lifecycle. Runs BEFORE the first request is accepted
    and AFTER the last request during graceful shutdown.

    STARTUP (before first request):
      1. Load ML model from disk (can take 5-60s for large models)
      2. Run warmup inference (model_loader.load() handles this)
      3. Only after successful load does FastAPI begin accepting connections
         → But K8s won't route traffic until /ready returns 200

    SHUTDOWN (after last request):
      This block runs when SIGTERM is received (K8s pod deletion).
      1. FastAPI stops accepting NEW requests (drain flag set by main process)
      2. In-flight requests complete (terminationGracePeriodSeconds gives them time)
      3. Code after `yield` runs: close DB connections, flush metrics, etc.

    KUBERNETES GRACEFUL SHUTDOWN SEQUENCE:
      K8s sends SIGTERM → preStop hook runs (sleep 5s, gives LB time to deregister)
      → lifespan shutdown block runs → pod terminates cleanly
      → No dropped requests (assuming terminationGracePeriodSeconds > max request duration)
    """
    # ── STARTUP ────────────────────────────────────────────────────────────────
    logger.info(f"Starting {APP_NAME} v{APP_VERSION}")
    logger.info(f"Model path: {os.getenv('MODEL_PATH', '/models/model.pkl')}")
    logger.info(f"Pod: {os.getenv('POD_NAME', 'unknown')} | Node: {os.getenv('NODE_NAME', 'unknown')}")

    try:
        # asyncio.to_thread: runs the blocking joblib.load() call in a thread pool
        # Without this: model loading blocks the event loop → no other requests handled
        # This is critical for large models (BERT, ResNet) that take minutes to load
        await asyncio.to_thread(model_loader.load)
        logger.info("Model loaded successfully — server is ready")
    except Exception as e:
        logger.critical(f"FATAL: Model loading failed: {e}")
        # Don't crash the process — let K8s readiness probe detect the issue.
        # The process stays alive but /ready returns 503 → K8s keeps pod out of LB.

    yield  # ← Application runs here (all request handling)

    # ── SHUTDOWN ────────────────────────────────────────────────────────────────
    logger.info("Shutdown signal received — draining in-flight requests...")
    # In production: close database connection pools, flush buffered metrics, etc.
    logger.info("Shutdown complete")


# ─── FASTAPI APPLICATION ───────────────────────────────────────────────────────
app = FastAPI(
    title=APP_NAME,
    description="""
## ML Inference Server — Wine Quality Classifier

Enterprise-grade FastAPI inference server serving a **GradientBoosting** classifier
trained on the UCI Wine Quality dataset. Deployed on Kubernetes with:
- Horizontal Pod Autoscaling (HPA) based on Prometheus metrics
- Init container for model artifact download
- Separate liveness and readiness probes
- Prometheus metrics at `/metrics`
- Structured JSON logging

### Production Architecture
```
Client → Ingress → Service → [Pod1|Pod2|Pod3] → PVC (model.pkl)
                              ↕
                          Prometheus → KEDA → HPA scaling
```
    """,
    version=APP_VERSION,
    lifespan=lifespan,
    docs_url="/docs",       # Swagger UI at /docs
    redoc_url="/redoc",     # ReDoc alternative at /redoc
    openapi_url="/openapi.json",
)

# ─── MIDDLEWARE ────────────────────────────────────────────────────────────────
# CORS: Allow cross-origin requests (for browser-based clients calling the API)
# In enterprise: restrict allowed_origins to your company's frontend domains
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "*").split(","),
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    """
    Middleware that logs EVERY request with timing and adds a trace ID.

    ENTERPRISE OBSERVABILITY:
      Every request gets a unique X-Request-ID header (UUIDv4).
      This ID is:
        - Returned in the response header → client can report it in bug reports
        - Logged in the server log → correlate with Prometheus traces
        - Forwarded downstream → end-to-end trace across microservices

      In a full observability stack: X-Request-ID is the "trace ID" that
      connects logs (Loki), metrics (Prometheus), and traces (Jaeger/Tempo).
    """
    # Generate or accept a trace ID from upstream (Ingress might set it)
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    start = time.monotonic()

    response = await call_next(request)

    elapsed_ms = (time.monotonic() - start) * 1000
    logger.info(
        f"request_id={request_id} "
        f"method={request.method} "
        f"path={request.url.path} "
        f"status={response.status_code} "
        f"duration_ms={elapsed_ms:.1f}"
    )

    response.headers["X-Request-ID"] = request_id
    response.headers["X-Server-Version"] = APP_VERSION
    return response


# ─── HEALTH ENDPOINTS ─────────────────────────────────────────────────────────
# These are called by Kubernetes every few seconds. They MUST be fast.
# No model access, no database calls, no I/O in liveness.

@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["Health"],
    summary="Liveness probe — is the server process alive?",
    status_code=200
)
async def health():
    """
    Kubernetes LIVENESS probe endpoint.

    Returns 200 always (if the process is alive, this endpoint responds).
    Never checks the model — the process being alive is sufficient for liveness.

    If this returns a non-2xx status → K8s RESTARTS the container.
    This should only happen if the server process is truly broken (deadlock, panic).
    """
    return HealthResponse(status="healthy", version=APP_VERSION)


@app.get(
    "/ready",
    response_model=ReadinessResponse,
    tags=["Health"],
    summary="Readiness probe — is the model loaded?",
)
async def ready():
    """
    Kubernetes READINESS probe endpoint.

    Returns 200 when model is loaded, 503 when not yet ready.
    K8s only routes traffic to this pod when this returns 200.

    CRITICAL BEHAVIOR:
      - During startup: returns 503 while model loads → no traffic sent
      - After load:     returns 200 → traffic begins
      - After OOM/crash (if model unloaded): returns 503 → pod removed from LB
                        (pod is NOT restarted — that's liveness's job)
    """
    meta = model_loader.metadata

    if model_loader.is_ready and meta:
        return ReadinessResponse(
            status="ready",
            model_loaded=True,
            model_version=meta.get("model_version"),
            model_name=meta.get("model_name"),
        )

    # Return 503 Service Unavailable — K8s interprets any non-2xx as "not ready"
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "status": "not_ready",
            "model_loaded": False,
            "error": model_loader.load_error or "Model loading in progress",
        }
    )


# ─── METRICS ENDPOINT ─────────────────────────────────────────────────────────

@app.get(
    "/metrics",
    response_class=PlainTextResponse,
    tags=["Observability"],
    summary="Prometheus metrics — scraped by Prometheus every 15s",
    include_in_schema=False,  # Don't show in Swagger (it's for machines, not humans)
)
async def metrics():
    """
    Prometheus metrics endpoint.

    ENTERPRISE SCRAPING FLOW:
      1. Prometheus (in monitoring namespace) is configured with a ServiceMonitor
      2. ServiceMonitor has: port=8000, path=/metrics, interval=15s
      3. Prometheus scrapes each pod every 15s
      4. Metrics include: inference latency histogram, prediction counter, model gauge
      5. KEDA ScaledObject queries: avg(ml_inference_latency_seconds_bucket)
      6. When P95 latency > 0.5s → KEDA increases targetReplicas in HPA
      7. HPA creates new pods → replicas increase → load distributes → latency drops

    WHAT THIS RETURNS (Prometheus text format):
      # HELP ml_predictions_total Total number of inference predictions served
      # TYPE ml_predictions_total counter
      ml_predictions_total{class_predicted="0",model_version="1.0.0",status="success"} 42.0
      ...
      # HELP ml_inference_latency_seconds Time taken for a single inference
      # TYPE ml_inference_latency_seconds histogram
      ml_inference_latency_seconds_bucket{le="0.005",model_version="1.0.0"} 38.0
      ...
    """
    return PlainTextResponse(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )


# ─── MODEL INFO ENDPOINT ──────────────────────────────────────────────────────

@app.get(
    "/model/info",
    response_model=ModelInfoResponse,
    tags=["Model"],
    summary="Model metadata — version, algorithm, training metrics",
)
async def model_info():
    """
    Returns metadata about the currently loaded model.
    Allows clients to know EXACTLY which model version they're talking to.

    ENTERPRISE USE:
      - Canary deployments: two Deployments with different model versions
        both behind the same Service → clients can log which version responded
      - Debugging: "The last N predictions were wrong" → check which version was running
      - Compliance: "Prove which model made this decision" → model_version in audit log
    """
    if not model_loader.is_ready or not model_loader.metadata:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Model not loaded"
        )
    meta = model_loader.metadata
    return ModelInfoResponse(
        name=meta["model_name"],
        version=meta["model_version"],
        algorithm=meta["algorithm"],
        framework=meta["framework"],
        trained_at=meta["trained_at"],
        metrics=meta["metrics"],
        input_features=meta["input_schema"]["features"],
        status=meta["status"],
    )


# ─── INFERENCE ENDPOINTS ──────────────────────────────────────────────────────

@app.post(
    "/api/v1/predict",
    response_model=PredictionResponse,
    tags=["Inference"],
    summary="Real-time single sample prediction",
    status_code=200,
)
async def predict(request: Request, payload: WineFeatures):
    """
    Real-time inference for a single wine sample.

    ENTERPRISE SLA TARGET: P99 latency < 100ms

    CONCURRENCY MODEL:
      FastAPI handles concurrent requests via asyncio.
      predict() is CPU-bound (sklearn inference), not I/O-bound.
      For true concurrency without blocking the event loop, we use
      asyncio.to_thread() to run inference in a thread pool executor.

      Without asyncio.to_thread():
        Request 1 → blocks event loop for 10ms during inference
        Requests 2-N → queued, can't even start

      With asyncio.to_thread():
        Request 1 → spins off to thread pool, event loop is FREE
        Requests 2-N → all start immediately in their own thread pool slots
        Throughput improvement: ~10-50x for CPU-bound inference
    """
    if not model_loader.is_ready:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Model not ready. Retry after a moment."
        )

    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))

    try:
        features = payload.to_feature_array()

        # Run CPU-bound inference in thread pool → doesn't block event loop
        # This is the correct pattern for ML inference in async FastAPI
        result = await asyncio.to_thread(model_loader.predict, features)
        result["request_id"] = request_id
        return PredictionResponse(**result)

    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e))
    except Exception as e:
        logger.error(f"Prediction error: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Inference failed. Check server logs for request_id: " + request_id
        )


@app.post(
    "/api/v1/predict/batch",
    response_model=BatchPredictionResponse,
    tags=["Inference"],
    summary="Batch prediction — up to 500 samples per request",
    status_code=200,
)
async def predict_batch(request: Request, payload: BatchPredictionRequest):
    """
    Vectorized batch inference.

    WHEN TO USE THIS ENDPOINT:
      - Analytics pipelines scoring historical data
      - Bulk predictions triggered by a data pipeline (Spark → FastAPI → results)
      - A/B test data scoring outside user-facing latency windows

    PERFORMANCE:
      Batch of 100 samples ≈ 2-5x faster than 100 individual /predict calls
      because sklearn vectorizes matrix operations across the batch.
      Large batches (>500) → use an offline batch inference Job instead of HTTP.
    """
    if not model_loader.is_ready:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Model not ready"
        )

    batch_features = [sample.to_feature_array() for sample in payload.samples]

    try:
        results = await asyncio.to_thread(model_loader.predict_batch, batch_features)
        model_version = model_loader.metadata.get("model_version", "unknown")
        return BatchPredictionResponse(
            predictions=[PredictionResponse(**r) for r in results],
            total_samples=len(results),
            model_version=model_version,
        )
    except Exception as e:
        logger.error(f"Batch prediction error: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Batch inference failed: {str(e)}"
        )


# ─── ROOT ENDPOINT ────────────────────────────────────────────────────────────

@app.get("/", tags=["Info"], include_in_schema=False)
async def root():
    """Root endpoint — redirects humans to docs."""
    return JSONResponse({
        "service": APP_NAME,
        "version": APP_VERSION,
        "docs": "/docs",
        "health": "/health",
        "ready": "/ready",
        "metrics": "/metrics",
        "model_info": "/model/info",
        "inference": "/api/v1/predict"
    })
