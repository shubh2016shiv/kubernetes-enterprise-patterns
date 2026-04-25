"""
Module: main
Purpose: Assemble and configure the wine quality inference FastAPI application.
         Own the ASGI lifespan: load the approved MLflow model at startup,
         wire application state, and mount route handlers.
Inputs:  Kubernetes environment variables (read via InferenceSettings at startup).
Outputs: FastAPI ASGI application consumed by Uvicorn.
Tradeoffs: Model loading happens in the ASGI lifespan context manager, not at
           import time. This means the pod starts fast (import is cheap),
           but the application must fail startup if loading fails. Kubernetes
           can only roll back cleanly when a bad model reference causes an
           obvious failed rollout instead of an alive-but-never-ready pod.

           An alternative is to load the model in a background thread at
           startup and accept requests on a secondary endpoint while loading.
           That pattern is appropriate for very large models with hour-scale
           load times. For this lab (sklearn Pipeline, sub-10-second load),
           the synchronous lifespan approach is clean and correct.
"""

from __future__ import annotations

# Standard library: contextlib for the ASGI lifespan context manager pattern.
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import AsyncGenerator

# Third-party: FastAPI for the HTTP layer and ASGI interface.
# Enterprise: In production, FastAPI sits behind an ingress controller (NGINX,
# AWS ALB, Istio gateway) and optionally an API gateway for rate limiting,
# authentication, and observability injection.
from fastapi import FastAPI

# Local: all application components imported explicitly. Each import reflects
# a single responsibility boundary. If an import name is ambiguous, that is a
# signal the module naming needs improvement.
from app.api.routes import router
from app.core.logging_config import configure_logging, get_logger
from app.core.settings import InferenceSettings, get_inference_settings
from app.health.health_checks import HealthCheckService
from app.model_loading.model_loader import ModelLoader
from app.prediction.prediction_service import PredictionService


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """
    Purpose:
        ASGI lifespan context manager. Everything before `yield` runs at
        startup. Everything after `yield` runs at shutdown. FastAPI executes
        this before the server begins accepting requests.

        The key action here is loading the approved MLflow model into memory.
        Until that completes successfully, the pod must not receive traffic. If
        loading fails, startup fails and Kubernetes/CI-CD rollout logic can stop
        the release and preserve the previous healthy ReplicaSet.

    Why use lifespan instead of startup events?
        FastAPI's @app.on_event("startup") is deprecated in favor of the
        lifespan context manager because the context manager approach allows
        sharing objects between startup and shutdown without global state, and
        it composes cleanly with async cleanup (closing connections, releasing
        GPU memory, draining inflight requests).

    ENTERPRISE EMPHASIS: The ASGI lifespan is the correct place for any
    one-time initialization that must complete before the pod is ready. This
    includes loading ML models, warming up connection pools, and verifying
    configuration against live dependencies. Doing these in route handlers
    (on first request) is slower and harder to reason about.

    ANTI-PATTERN TO AVOID: Do not swallow model-load failures and keep the
    process alive forever. Readiness failures remove a pod from Service traffic,
    but they do not restart the container. A pod with a bad MODEL_URI should fail
    startup so the rollout clearly fails and rollback automation can act.
    """
    settings: InferenceSettings = get_inference_settings()

    # Configure structured JSON logging before any log statements fire.
    configure_logging(settings.log_level)
    logger = get_logger(__name__)

    startup_time = datetime.now(timezone.utc)

    logger.info(
        "Inference API startup",
        extra={
            "service": settings.app_name,
            "environment": settings.app_environment,
            "model_uri": settings.model_uri,
            "model_version": settings.model_version,
            "registry_name": settings.model_registry_name,
            "pod_name": settings.pod_name,
            "pod_namespace": settings.pod_namespace,
        },
    )

    # Create the health service early so it can mark model load failures.
    # It starts with model_loaded=False, which makes /health/ready return
    # HTTP 503 immediately, before the model loading attempt begins.
    health_service = HealthCheckService(
        settings=settings,
        startup_time=startup_time,
    )

    # Store health_service in app.state before model loading so the readiness
    # probe can already respond (with HTTP 503) during the loading window.
    # Without this, /health/ready would return HTTP 500 during loading because
    # the route handler would find no health_service in app.state.
    app.state.settings = settings
    app.state.health_service = health_service

    # ─────────────────────────────────────────────────────────────────────
    # Load the approved model artifact.
    # This is the most important step in the lifespan. The MODEL_URI env var
    # was set by the CI/CD release bridge to an immutable version such as
    # models:/wine-quality-classifier-prod/1. The pod connects to the MLflow
    # Tracking Server, downloads the artifact, and deserializes the sklearn
    # Pipeline into memory.
    #
    # If loading fails (server unreachable, artifact missing, deserialization
    # error), record the failure for logs and then re-raise. This intentionally
    # fails startup. Kubernetes marks the new ReplicaSet unhealthy, keeps old
    # ready pods serving, and lets rollout-approved-model.sh roll back.
    # ─────────────────────────────────────────────────────────────────────
    try:
        loader = ModelLoader(settings=settings)
        loaded_model = loader.load()

        # Wire services that depend on the loaded model.
        prediction_service = PredictionService(loaded_model=loaded_model)

        app.state.loaded_model = loaded_model
        app.state.prediction_service = prediction_service

        # Mark the pod as ready. After this call, /health/ready returns HTTP 200
        # and Kubernetes adds this pod to the Service endpoint set.
        health_service.mark_model_loaded()

    except Exception as exc:  # noqa: BLE001
        error_message = f"model load failed: {exc}"
        health_service.mark_model_failed(error_message)
        logger.error(
            "Model load failed — pod is not ready",
            extra={"error": str(exc), "model_uri": settings.model_uri},
        )
        # ENTERPRISE EMPHASIS: Fail fast. Kubernetes readiness probes do not
        # restart containers; they only remove a pod from Service endpoints. If
        # the configured model cannot load, this pod is not a valid deployment.
        # Re-raising makes the container exit, which surfaces a clear
        # CrashLoopBackOff/failed rollout instead of a silent, permanently
        # unready pod.
        raise

    yield  # Pod is now serving requests. Routes are live.

    # ─────────────────────────────────────────────────────────────────────
    # Shutdown: runs after Kubernetes sends SIGTERM and waits terminationGracePeriod.
    # ─────────────────────────────────────────────────────────────────────
    logger.info(
        "Inference API shutdown",
        extra={
            "service": settings.app_name,
            "model_uri": settings.model_uri,
        },
    )
    # sklearn Pipelines have no explicit close/cleanup. If future model types
    # need resource release (GPU memory, file handles), add them here.


def create_application() -> FastAPI:
    """
    Purpose:
        Build and configure the FastAPI application instance.
        Using an application factory (function that returns the app) rather than
        a module-level `app = FastAPI()` makes the app easier to test and
        avoids import-time side effects.
    Return value:
        Configured FastAPI app with lifespan, middleware, and routes mounted.
    Enterprise equivalent:
        Application factories are standard in enterprise FastAPI projects
        because they allow test suites to create isolated app instances per
        test without sharing state.
    """
    settings = get_inference_settings()

    application = FastAPI(
        title="Wine Quality Inference API",
        version=settings.app_version,
        description=(
            "Kubernetes-native inference API that loads an approved wine cultivar "
            "classifier from the MLflow Model Registry and serves predictions "
            "via a typed REST endpoint. The model version served by this pod is "
            "pinned at deployment time by the CI/CD release bridge."
        ),
        lifespan=lifespan,
    )

    # Mount all routes from the router. The empty prefix means routes are
    # accessible at /health/live, /health/ready, /predict, and / directly.
    application.include_router(router)

    return application


# Uvicorn entry point: `uvicorn app.main:app --host 0.0.0.0 --port 8080`
# The application is built once when this module is imported by Uvicorn.
app = create_application()
