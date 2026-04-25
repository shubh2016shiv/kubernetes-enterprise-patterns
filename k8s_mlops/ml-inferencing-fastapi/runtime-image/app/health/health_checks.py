"""
Module: health_checks
Purpose: Implement Kubernetes liveness and readiness health check logic for the
         inference API. Readiness depends on model load status. Liveness depends
         only on process responsiveness.
Inputs:  InferenceSettings and the model load state from application state.
Outputs: Typed health response dictionaries consumed by route handlers.
Tradeoffs: Liveness and readiness are deliberately separated because they
           answer different questions. Merging them into one endpoint is a
           common mistake that causes Kubernetes to restart healthy pods
           whenever a downstream dependency (MLflow) is temporarily unavailable.
"""

from __future__ import annotations

# Standard library: datetime for uptime calculation.
from datetime import datetime, timezone
from typing import Any

# Local: settings for metadata, model state for the readiness gate.
from app.core.logging_config import get_logger
from app.core.settings import InferenceSettings

logger = get_logger(__name__)


class HealthCheckService:
    """
    Purpose:
        Provide the liveness and readiness status for the inference pod.
        These are the two endpoints Kubernetes probes throughout the pod's
        lifetime to decide whether to route traffic (readiness) or restart
        the process (liveness).

    Why two separate endpoints matter:
        Liveness (/health/live): "Is the process alive and responsive?"
          → If NO: Kubernetes restarts the container.
          → Should fail only when the process is truly broken (deadlock, OOM).
          → Must NOT fail just because the model is still loading.

        Readiness (/health/ready): "Is the service ready to serve predictions?"
          → If NO: Kubernetes removes the pod from Service endpoints.
          → Should fail until the model artifact is fully loaded into memory.
          → If the MLflow server is temporarily unavailable but the model is
             already loaded, readiness should remain true (the pod can still
             predict from the in-memory model).

    ENTERPRISE EMPHASIS: A common misconfiguration is setting the liveness probe
    to check model loading status. If a model takes 60 seconds to load, and the
    liveness probe fails after 30 seconds, Kubernetes restarts the pod in an
    infinite loop. The model never loads. Use a startupProbe with a long timeout
    for the initial model load window, then switch to a fast liveness probe for
    the running state.

    Parameters:
        settings: InferenceSettings instance.
        startup_time: UTC timestamp when the ASGI lifespan started.
    """

    def __init__(
        self,
        settings: InferenceSettings,
        startup_time: datetime,
    ) -> None:
        self._settings = settings
        self._startup_time = startup_time

        # _model_loaded is set to True by the ASGI lifespan after the model
        # loader completes successfully. Readiness depends on this flag.
        # It starts False so no traffic reaches /predict before load completes.
        self._model_loaded: bool = False
        self._load_error: str | None = None

    def mark_model_loaded(self) -> None:
        """
        Purpose:
            Set the readiness flag to True after successful model load.
            Called by the ASGI lifespan handler, not by route handlers.
        """
        self._model_loaded = True
        self._load_error = None
        logger.info(
            "Model loaded — pod is now ready to serve predictions",
            extra={"model_uri": self._settings.model_uri},
        )

    def mark_model_failed(self, error: str) -> None:
        """
        Purpose:
            Record a model load failure so the readiness endpoint can explain
            why the pod is not ready. The pod stays in a not-ready state and
            Kubernetes holds it out of the Service endpoint set.
        Parameters:
            error: Human-readable description of the load failure.
        """
        self._model_loaded = False
        self._load_error = error
        logger.error(
            "Model load failed — pod will not serve predictions",
            extra={"error": error, "model_uri": self._settings.model_uri},
        )

    @property
    def is_ready(self) -> bool:
        """Return True only when the model has been loaded successfully."""
        return self._model_loaded

    def get_liveness(self) -> dict[str, Any]:
        """
        Purpose:
            Return process liveness status. Liveness checks only that the
            Python process is alive and can execute. It does not check model
            state or downstream dependencies.
        Return value:
            Dict with status=alive and process metadata. FastAPI serializes
            this as the HTTP 200 JSON response body.
        Failure behavior:
            This method should almost never fail. If it does, the exception
            propagates to FastAPI, which returns HTTP 500, which fails the
            liveness probe and causes Kubernetes to restart the container.
        Enterprise equivalent:
            Liveness probes in production are typically a lightweight ping
            endpoint. Some platforms use TCP socket checks instead of HTTP for
            liveness because TCP probes add zero application overhead.

        ENTERPRISE EMPHASIS: Do NOT add model loading checks to liveness.
        A pod that is alive but still loading the model is not a dead process.
        Killing it wastes the loading work done so far and starts a restart loop.
        """
        now = datetime.now(timezone.utc)
        uptime_seconds = (now - self._startup_time).total_seconds()

        return {
            "status": "alive",
            "service": self._settings.app_name,
            "environment": self._settings.app_environment,
            "pod_name": self._settings.pod_name,
            "pod_namespace": self._settings.pod_namespace,
            "node_name": self._settings.node_name,
            "uptime_seconds": round(uptime_seconds, 1),
        }

    def get_readiness(self) -> dict[str, Any]:
        """
        Purpose:
            Return readiness status. This endpoint must return HTTP 503 until
            the model has been loaded into memory. Traffic must not reach the
            /predict endpoint before the model is ready.
        Return value:
            Dict with status=ready or status=not_ready plus model metadata.
            The route handler returns HTTP 200 for ready and HTTP 503 for
            not-ready.
        Failure behavior:
            If self._model_loaded is False, the route handler raises HTTP 503.
            Kubernetes removes this pod from the Service endpoint set, sending
            requests to other pods that are already ready.
        Enterprise equivalent:
            In production, readiness often also checks secondary dependencies
            such as a feature store, a vector database, or a GPU allocator.
            The contract is: if this pod cannot serve good predictions, it should
            not receive traffic. Readiness expresses that contract.

        ENTERPRISE EMPHASIS: Do NOT make readiness depend on external systems
        that the pod cannot control (e.g., the MLflow server's availability after
        model load). Once the model is loaded, the pod can serve predictions
        independently of MLflow. Making readiness depend on MLflow health would
        cause all pods to become unready simultaneously if MLflow restarts,
        which is a service-wide outage caused by a monitoring dependency.
        """
        base = {
            "service": self._settings.app_name,
            "pod_name": self._settings.pod_name,
            "model_uri": self._settings.model_uri,
            "model_version": self._settings.model_version,
            "registry_name": self._settings.model_registry_name,
        }

        if self._model_loaded:
            return {**base, "status": "ready"}

        error_detail = self._load_error or "model not yet loaded"
        return {**base, "status": "not_ready", "reason": error_detail}
