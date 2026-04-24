"""
=============================================================================
FILE: ml-serving/05-custom-fastapi-serving/runtime-image/app/model_loader.py
PURPOSE: Model artifact lifecycle management — load, validate, cache, and
         expose the model with thread-safe access for concurrent requests.

ENTERPRISE CONTEXT:
  The ModelLoader is the most critical component of any inference server.
  It must handle:
    1. Artifact sourcing:   Local path (dev) or cloud storage (prod)
    2. Integrity checks:    SHA-256 validation before loading untrusted artifacts
    3. Thread safety:       Many concurrent FastAPI requests hit predict() simultaneously
    4. Graceful startup:    K8s readiness probe depends on is_ready() returning True
    5. Hot-swap (advanced): Replace the model without restarting the pod
    6. Metrics tracking:    Request count, latency, error rate for HPA scaling
=============================================================================
"""

import hashlib
import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Optional

import joblib
import numpy as np

# prometheus_client: industry-standard metrics library for Python
# Metrics exposed at /metrics are scraped by Prometheus in enterprise
# These metrics feed the HPA (Horizontal Pod Autoscaler) for scaling decisions
from prometheus_client import Counter, Histogram, Gauge

# ─── LOGGING SETUP ────────────────────────────────────────────────────────────
# Structured logging in production. In enterprise, these logs go to:
#   ELK Stack (Elasticsearch + Logstash + Kibana)
#   Loki + Grafana
#   CloudWatch Logs (AWS)
#   Cloud Logging (GCP)
# The sidecar log shipper we built in 03-pods reads these from the shared volume.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S"
)
logger = logging.getLogger("model_loader")

# ─── PROMETHEUS METRICS ───────────────────────────────────────────────────────
# These metrics are THE foundation for enterprise ML observability and scaling.
# Every inference server should expose these at minimum.

# COUNTER: Total predictions made (monotonically increasing, never resets)
# Used for: throughput dashboards, SLA tracking, capacity planning
PREDICTION_COUNTER = Counter(
    "ml_predictions_total",
    "Total number of inference predictions served",
    ["model_version", "class_predicted", "status"]  # label dimensions
    # status="success" or "error"
)

# HISTOGRAM: Inference latency distribution
# This is THE most important metric for ML serving quality.
# In enterprise: P50 (median), P95, P99 latencies are tracked.
# HPA scales on P95 latency via KEDA + Prometheus adapter.
# Buckets represent latency thresholds in seconds:
#   0.001 = 1ms,  0.005 = 5ms,  0.010 = 10ms, ...  1.0 = 1 second
INFERENCE_LATENCY = Histogram(
    "ml_inference_latency_seconds",
    "Time taken for a single inference prediction",
    ["model_version"],
    buckets=[0.001, 0.005, 0.010, 0.025, 0.050, 0.100, 0.250, 0.500, 1.0, 2.5]
)

# GAUGE: Current model loading state (0=not loaded, 1=loaded, -1=error)
# Used by the readiness probe check and Grafana dashboard status panels
MODEL_LOADED_GAUGE = Gauge(
    "ml_model_loaded",
    "Whether the ML model is currently loaded and ready",
    ["model_name", "model_version"]
)

# COUNTER: Model load attempts and outcomes (for alerting on load failures)
MODEL_LOAD_COUNTER = Counter(
    "ml_model_load_total",
    "Total model load attempts",
    ["status"]  # "success" or "failure"
)


class ModelLoader:
    """
    Thread-safe singleton for ML model lifecycle management.

    SINGLETON PATTERN:
      We create ONE instance at application startup and reuse it for all requests.
      This is critical because model loading is expensive (seconds to minutes).
      Loading the model per-request would make the server 100x slower.

    THREAD SAFETY:
      FastAPI runs request handlers concurrently (asyncio + thread pool).
      We use threading.Lock() to protect the model reference during hot-swap.
      Read operations (predict) don't need the lock because Python's GIL
      ensures dict/object reads are atomic for single references.
      Write operations (load, reload) acquire the lock to prevent a request
      from using a half-loaded model.
    """

    def __init__(self):
        # ── Model state ───────────────────────────────────────────────────────
        self._model = None          # The sklearn Pipeline object
        self._metadata = None       # dict from model_metadata.json
        self._model_lock = threading.Lock()  # Protects model swap operations
        self._loaded = False        # Readiness flag (checked by K8s readiness probe)
        self._load_error: Optional[str] = None  # Last error during load (for debug)
        self._load_time: Optional[float] = None  # When model was loaded (Unix timestamp)

        # ── Configuration from environment variables ─────────────────────────
        # All paths come from env vars → can be changed via ConfigMap without rebuilding image
        # Local: MODEL_PATH = "/models/model.pkl" (PVC mount in K8s)
        # Production: MODEL_PATH is still local after init container downloads from S3
        self.model_path = Path(
            os.getenv("MODEL_PATH", "/models/model.pkl")
        )
        self.metadata_path = Path(
            os.getenv("MODEL_METADATA_PATH", "/models/model_metadata.json")
        )
        # VALIDATE_CHECKSUM: disable in dev, always enable in prod
        self.validate_checksum = os.getenv("VALIDATE_CHECKSUM", "true").lower() == "true"

        logger.info(f"ModelLoader initialized | model_path={self.model_path}")

    def load(self) -> None:
        """
        Load the model artifact from disk.
        Called ONCE at application startup in FastAPI's lifespan event.

        LOADING SEQUENCE:
          1. Verify the artifact file exists
          2. Load metadata JSON (get expected checksum + schema)
          3. Validate SHA-256 checksum (artifact integrity)
          4. Load the pkl via joblib.load()
          5. Run a warmup inference (initializes lazy-loaded buffers)
          6. Set _loaded = True → readiness probe starts returning 200

        WARMUP INFERENCE (step 5):
          When the model receives its VERY FIRST request after loading, some
          sklearn implementations initialize internal caches/buffers.
          This causes the first real user request to be ~100-500ms slower.
          By sending a dummy request during startup (before K8s marks us Ready),
          the first real user request hits a fully warm model.
          This is the "model warm-up" pattern used in all production inference servers.
        """
        logger.info("Starting model load sequence...")
        start = time.monotonic()

        try:
            # Step 1: File existence
            if not self.model_path.exists():
                raise FileNotFoundError(
                    f"Model artifact not found: {self.model_path}\n"
                    f"In K8s: check PVC mount and init container logs.\n"
                    f"Local: run `python model/train_and_save.py` first."
                )

            # Step 2: Load metadata
            self._metadata = self._load_metadata()
            model_name = self._metadata.get("model_name", "unknown")
            model_version = self._metadata.get("model_version", "unknown")
            logger.info(f"Metadata loaded | model={model_name} version={model_version}")

            # Step 3: SHA-256 integrity check
            if self.validate_checksum:
                self._validate_checksum()

            # Step 4: Load the model pipeline
            logger.info(f"Loading model artifact: {self.model_path}")
            with self._model_lock:
                self._model = joblib.load(self.model_path)

            logger.info(f"Model loaded | type={type(self._model).__name__}")

            # Step 5: Warmup inference
            self._warmup()

            # Step 6: Mark as ready
            self._loaded = True
            self._load_time = time.monotonic()
            self._load_error = None

            elapsed = time.monotonic() - start
            logger.info(f"Model ready | load_time={elapsed:.3f}s | version={model_version}")

            # Update Prometheus gauge: model is loaded
            MODEL_LOADED_GAUGE.labels(
                model_name=model_name,
                model_version=model_version
            ).set(1)
            MODEL_LOAD_COUNTER.labels(status="success").inc()

        except Exception as e:
            self._loaded = False
            self._load_error = str(e)
            MODEL_LOAD_COUNTER.labels(status="failure").inc()
            logger.error(f"Model load FAILED: {e}", exc_info=True)
            # Re-raise: FastAPI startup will catch this.
            # If model fails to load, the pod should NOT start serving traffic.
            # K8s readiness probe will fail → pod removed from Service endpoints.
            raise

    def _load_metadata(self) -> dict:
        """Load and parse model_metadata.json."""
        if not self.metadata_path.exists():
            raise FileNotFoundError(f"Metadata not found: {self.metadata_path}")
        with open(self.metadata_path) as f:
            return json.load(f)

    def _validate_checksum(self) -> None:
        """
        Compute SHA-256 of model.pkl and compare to metadata.
        Raises ValueError if checksum mismatches.
        """
        expected = self._metadata.get("sha256")
        if not expected:
            logger.warning("No checksum in metadata — skipping validation")
            return

        logger.info("Validating model checksum...")
        sha256 = hashlib.sha256()
        with open(self.model_path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                sha256.update(chunk)
        actual = sha256.hexdigest()

        if actual != expected:
            raise ValueError(
                f"Model checksum MISMATCH!\n"
                f"  Expected: {expected}\n"
                f"  Actual:   {actual}\n"
                f"The artifact may be corrupted or tampered with."
            )
        logger.info(f"Checksum validated: {actual[:16]}...")

    def _warmup(self) -> None:
        """
        Run a synthetic inference to warm up all internal buffers.
        Uses mean feature values from metadata if available,
        otherwise uses all-zeros (safe for GradientBoosting).
        """
        logger.info("Running warmup inference...")
        feature_count = self._metadata["input_schema"]["feature_count"]
        dummy_input = np.zeros((1, feature_count), dtype=np.float64)
        _ = self._model.predict(dummy_input)
        _ = self._model.predict_proba(dummy_input)
        logger.info("Warmup complete")

    def predict(self, features: list[float]) -> dict:
        """
        Run inference for a single sample.
        This is called for every /predict request — must be fast.

        CONCURRENCY NOTE:
          This method does NOT acquire _model_lock for reads.
          Python's GIL + the atomic nature of object reference reads means
          concurrent predict() calls on the same _model are safe.
          We only lock during model swap (load/reload operations).
        """
        if not self._loaded:
            raise RuntimeError("Model not loaded. Check readiness probe.")

        model_version = self._metadata.get("model_version", "unknown")
        start = time.monotonic()

        try:
            # Reshape to 2D array: sklearn requires shape (n_samples, n_features)
            # features is a flat list → [[f1, f2, ..., f13]]
            X = np.array(features, dtype=np.float64).reshape(1, -1)

            # predict() goes through the full Pipeline:
            #   1. StandardScaler transforms the input
            #   2. GradientBoostingClassifier returns class label
            predicted_class = int(self._model.predict(X)[0])

            # predict_proba() returns probability for each class
            # Shape: (1, n_classes) → we take index [0] to get the flat array
            probabilities = self._model.predict_proba(X)[0]

            target_names = self._metadata.get("target_names", ["class_0", "class_1", "class_2"])
            class_name = target_names[predicted_class]

            # Record Prometheus metrics
            latency = time.monotonic() - start
            INFERENCE_LATENCY.labels(model_version=model_version).observe(latency)
            PREDICTION_COUNTER.labels(
                model_version=model_version,
                class_predicted=str(predicted_class),
                status="success"
            ).inc()

            return {
                "predicted_class": predicted_class,
                "class_name": class_name,
                "probabilities": {
                    name: round(float(prob), 4)
                    for name, prob in zip(target_names, probabilities)
                },
                "model_version": model_version,
            }

        except Exception as e:
            latency = time.monotonic() - start
            INFERENCE_LATENCY.labels(model_version=model_version).observe(latency)
            PREDICTION_COUNTER.labels(
                model_version=model_version,
                class_predicted="error",
                status="error"
            ).inc()
            logger.error(f"Prediction failed: {e}", exc_info=True)
            raise

    def predict_batch(self, batch_features: list[list[float]]) -> list[dict]:
        """
        Vectorized batch inference — MUCH more efficient than serial predict() calls.
        sklearn's Pipeline processes all samples in the batch simultaneously.
        """
        if not self._loaded:
            raise RuntimeError("Model not loaded")

        model_version = self._metadata.get("model_version", "unknown")
        start = time.monotonic()
        n = len(batch_features)

        X = np.array(batch_features, dtype=np.float64)  # shape: (n_samples, n_features)
        predicted_classes = self._model.predict(X)        # shape: (n_samples,)
        all_probabilities = self._model.predict_proba(X)  # shape: (n_samples, n_classes)

        target_names = self._metadata.get("target_names", ["class_0", "class_1", "class_2"])

        results = []
        for i in range(n):
            predicted_class = int(predicted_classes[i])
            results.append({
                "predicted_class": predicted_class,
                "class_name": target_names[predicted_class],
                "probabilities": {
                    name: round(float(prob), 4)
                    for name, prob in zip(target_names, all_probabilities[i])
                },
                "model_version": model_version,
            })

        latency = time.monotonic() - start
        INFERENCE_LATENCY.labels(model_version=model_version).observe(latency / n)  # per-sample
        logger.info(f"Batch inference | n={n} | total_latency={latency:.3f}s | per_sample={latency/n*1000:.1f}ms")

        return results

    @property
    def is_ready(self) -> bool:
        """
        Thread-safe readiness check.
        Called by the /ready endpoint on every Kubernetes readiness probe.
        Must be O(1) — no I/O, no model access.
        """
        return self._loaded

    @property
    def metadata(self) -> Optional[dict]:
        return self._metadata

    @property
    def load_error(self) -> Optional[str]:
        return self._load_error
