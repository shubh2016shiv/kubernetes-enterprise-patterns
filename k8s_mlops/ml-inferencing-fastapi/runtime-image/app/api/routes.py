"""
Module: routes
Purpose: Define FastAPI HTTP route handlers for prediction and health endpoints.
         Route handlers are thin orchestration layers: they receive validated
         requests, call service objects, and return typed responses. Business
         logic lives in prediction_service.py and health_checks.py.
Inputs:  FastAPI Request objects with validated Pydantic bodies.
Outputs: HTTP responses with JSON bodies matching the declared response models.
Tradeoffs: This module uses FastAPI's APIRouter so routes can be mounted at
           a versioned prefix (/v1) if needed. All service dependencies come
           from application state set during ASGI lifespan — no globals.
"""

from __future__ import annotations

# Third-party: FastAPI for HTTP routing and dependency injection.
from fastapi import APIRouter, HTTPException, Request, status

# Local: request/response schemas and service types. Routes know about schemas
# and services but not about MLflow, pandas, or model loading internals.
from app.core.logging_config import get_logger
from app.core.settings import InferenceSettings
from app.health.health_checks import HealthCheckService
from app.prediction.prediction_service import PredictionService
from app.prediction.schemas import WineQualityFeatures, WineQualityPrediction

logger = get_logger(__name__)

# APIRouter groups endpoints that share a prefix or tag. The router is mounted
# in main.py. Using a router instead of decorating the FastAPI app directly
# makes it easier to version the API or enable/disable endpoint groups.
router = APIRouter()


@router.get("/health/live", tags=["health"], summary="Liveness probe")
def liveness(request: Request) -> dict:
    """
    Purpose:
        Kubernetes liveness probe endpoint. Returns HTTP 200 if the process is
        alive and responsive. This endpoint must never fail due to model loading
        state or external dependency availability.
    Parameters:
        request: FastAPI Request object providing access to app.state.
    Return value:
        JSON with status=alive and process metadata.
    Failure behavior:
        Only fails if the Python process cannot execute route handlers at all,
        which would indicate a severe process-level failure.
    Enterprise equivalent:
        This is the Kubernetes liveness probe target. If it fails for
        failureThreshold consecutive probe periods, Kubernetes restarts the
        container. Configure a long initialDelaySeconds or use a startupProbe
        to avoid restarting pods that are still loading their model.
    """
    health_service: HealthCheckService = request.app.state.health_service
    return health_service.get_liveness()


@router.get("/health/ready", tags=["health"], summary="Readiness probe")
def readiness(request: Request) -> dict:
    """
    Purpose:
        Kubernetes readiness probe endpoint. Returns HTTP 200 when the model
        is loaded and the pod can serve predictions. Returns HTTP 503 while
        the model is loading or if loading failed.
    Parameters:
        request: FastAPI Request object providing access to app.state.
    Return value:
        HTTP 200 JSON with status=ready when the model is loaded.
        HTTP 503 JSON with status=not_ready and a reason when not ready.
    Failure behavior:
        HTTP 503 causes Kubernetes to remove this pod from the Service
        endpoint set. Traffic is routed to other pods that are ready.
        When this pod's model finishes loading, it rejoins the endpoint set.
    Enterprise equivalent:
        The readiness endpoint is the traffic gate for ML pods during rollouts.
        It prevents new model version pods from receiving traffic before the
        model artifact is fully deserialized in memory, which prevents
        prediction errors during the loading window.

    ENTERPRISE EMPHASIS: The readiness probe is what makes zero-downtime model
    rollouts possible. Without it, Kubernetes might send requests to new pods
    before their model is ready, causing HTTP 500 errors during the brief
    model-loading window of each pod.
    """
    health_service: HealthCheckService = request.app.state.health_service

    if not health_service.is_ready:
        readiness_status = health_service.get_readiness()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=readiness_status,
        )

    return health_service.get_readiness()


@router.post(
    "/predict",
    response_model=WineQualityPrediction,
    tags=["inference"],
    summary="Wine cultivar classification",
)
def predict(
    features: WineQualityFeatures,
    request: Request,
) -> WineQualityPrediction:
    """
    Purpose:
        Accept 13 wine chemical measurement features and return a predicted
        cultivar class from the approved production model.
    Parameters:
        features: WineQualityFeatures body validated by Pydantic/FastAPI.
                  Invalid or missing fields return HTTP 422 before this handler
                  executes.
        request:  FastAPI Request providing access to app.state services.
    Return value:
        WineQualityPrediction with predicted class, label, and model version.
    Failure behavior:
        HTTP 503 if the model is not yet ready (client should retry).
        HTTP 500 if the prediction service raises an unexpected exception.
        Both cases include a detail field for the caller to log.
    Enterprise equivalent:
        In production, this endpoint is behind a rate limiter, a request
        authentication middleware, and a distributed tracing span. The response
        includes a trace ID so any prediction can be correlated with logs across
        the ingress controller, the inference pod, and any upstream feature
        service.

    ENTERPRISE EMPHASIS: The route handler does not contain any ML logic.
    It calls the prediction service, which calls the loaded model. If the
    prediction logic needs to change (pre-processing, calibration, business
    rules), the change lives in prediction_service.py — not here. This keeps
    routes testable as pure HTTP orchestration.
    """
    health_service: HealthCheckService = request.app.state.health_service

    # Guard: if the model is not loaded (e.g., pod came up but loading failed),
    # return HTTP 503 instead of a 500 from the prediction service. This gives
    # callers a retry-able status code rather than a non-retryable error.
    if not health_service.is_ready:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="model is not ready — please retry in a few seconds",
        )

    prediction_service: PredictionService = request.app.state.prediction_service

    try:
        return prediction_service.predict(features)
    except Exception as exc:
        logger.error(
            "Prediction failed",
            extra={"error": str(exc), "model_uri": request.app.state.loaded_model.model_uri},
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"prediction failed: {exc}",
        ) from exc


@router.get("/", tags=["metadata"], summary="Service metadata")
def service_metadata(request: Request) -> dict:
    """
    Purpose:
        Return deployment identity information for quick smoke tests and
        incident triage. Shows the service name, environment, model version,
        and pod identity without requiring any ML computation.
    Return value:
        Dict with service, environment, model_version, and pod metadata.
    Enterprise equivalent:
        This endpoint is used by smoke tests, monitoring dashboards, and
        incident responders to confirm which model version is serving traffic
        on a specific pod without checking the ConfigMap or deployment spec.
    """
    settings: InferenceSettings = request.app.state.settings

    return {
        "service": settings.app_name,
        "environment": settings.app_environment,
        "app_version": settings.app_version,
        "model_version": settings.model_version,
        "model_uri": settings.model_uri,
        "registry_name": settings.model_registry_name,
        "pod_name": settings.pod_name,
        "pod_namespace": settings.pod_namespace,
        "node_name": settings.node_name,
    }
