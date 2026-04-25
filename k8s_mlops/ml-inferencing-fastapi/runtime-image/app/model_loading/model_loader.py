"""
Module: model_loader
Purpose: Load the approved MLflow model artifact into memory at application
         startup and provide a thread-safe handle for the prediction service.
Inputs:  An immutable model URI from InferenceSettings (MODEL_URI env var).
Outputs: A LoadedModel container holding the pyfunc model and load metadata.
Tradeoffs: The model is loaded once at startup and held in memory for the pod's
           lifetime. This is the correct pattern for serving latency. The
           alternative — loading the model on each request — would add hundreds
           of milliseconds per call and is only appropriate for very large models
           that cannot fit in RAM simultaneously across replicas.
"""

from __future__ import annotations

# Standard library: dataclasses for the typed container, time for load duration.
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

# Local: settings and structured logging.
from app.core.logging_config import get_logger
from app.core.settings import InferenceSettings

logger = get_logger(__name__)


@dataclass
class LoadedModel:
    """
    Purpose:
        Hold the in-memory model and its load metadata in a single typed object.
        Passed to the prediction service via FastAPI application state.

    Fields:
        pyfunc_model:   The mlflow.pyfunc model handle. Exposes .predict(df).
        model_uri:      The immutable URI this model was loaded from. Logged
                        with every prediction for full auditability.
        model_version:  Human-readable version string for health responses.
        registry_name:  Registry name for identification in logs.
        loaded_at:      UTC timestamp when the model was loaded successfully.
        load_duration_seconds: Time taken to download and deserialize the model.

    Enterprise equivalent:
        Enterprise serving platforms record model load time as a startup metric
        to detect artifact size regressions between versions. A version that
        takes 30 seconds to load instead of 5 seconds is a warning signal.

    ENTERPRISE EMPHASIS: The LoadedModel object is created once and shared
    across all request handlers. This means the sklearn Pipeline deserialized
    from the artifact is not thread-safe for concurrent writes, but scikit-learn
    predict() is read-only (no model state changes during prediction). Multiple
    concurrent requests calling predict() on the same object is safe.
    """

    pyfunc_model: object
    model_uri: str
    model_version: str
    registry_name: str
    loaded_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    load_duration_seconds: float = 0.0


class ModelLoader:
    """
    Purpose:
        Encapsulate the logic for loading an MLflow pyfunc model from a given
        URI. Separating this into its own class makes it straightforward to swap
        the loading backend (e.g., from MLflow pyfunc to ONNX Runtime or
        TorchScript) without changing the prediction service or health module.
    Parameters:
        settings: Validated InferenceSettings object.
    Enterprise equivalent:
        In production, this class might extend to support loading from a model
        cache layer, verifying artifact checksums, or loading multiple model
        versions for A/B testing. Keeping it separate from the prediction service
        makes those extensions possible without touching business logic.
    """

    def __init__(self, settings: InferenceSettings) -> None:
        self._settings = settings

    def load(self) -> LoadedModel:
        """
        Purpose:
            Download and deserialize the MLflow model artifact. Set the MLflow
            tracking URI from settings so the pyfunc client knows which server
            to contact for artifact retrieval.
        Return value:
            LoadedModel with the pyfunc model handle and load metadata.
        Failure behavior:
            Raises an exception if the MLflow server is unreachable, if the
            model URI does not exist, or if deserialization fails. The exception
            propagates to the ASGI lifespan handler, which prevents the pod
            from becoming ready and causes Kubernetes to restart it.
        Enterprise equivalent:
            Production inference pods are expected to fail-fast if the model
            artifact cannot be loaded. A pod that starts without a valid model
            but accepts requests would silently return errors for every
            prediction, which is harder to detect than a failed readiness probe.

        ENTERPRISE EMPHASIS: Model loading is the readiness gate. The
        readiness probe at /health/ready must return HTTP 503 until this
        method completes successfully. Traffic must never reach /predict while
        model loading is still in progress or has failed.
        """
        # Import mlflow at load time so the module can be imported in
        # test environments that have mlflow mocked out.
        import mlflow

        # Set the MLflow tracking URI globally for the pyfunc loader client.
        # This is the server the pod uses to download the artifact files.
        # In the local lab: http://host.docker.internal:5000 (WSL2 host gateway).
        # In enterprise: https://mlflow.internal.company.com with mTLS.
        mlflow.set_tracking_uri(self._settings.mlflow_tracking_uri)

        logger.info(
            "Starting model load from MLflow registry",
            extra={
                "model_uri": self._settings.model_uri,
                "model_version": self._settings.model_version,
                "registry_name": self._settings.model_registry_name,
                "mlflow_tracking_uri": self._settings.mlflow_tracking_uri,
            },
        )

        start = time.monotonic()

        pyfunc_model = mlflow.pyfunc.load_model(self._settings.model_uri)

        duration = time.monotonic() - start

        logger.info(
            "Model loaded successfully",
            extra={
                "model_uri": self._settings.model_uri,
                "model_version": self._settings.model_version,
                "load_duration_seconds": round(duration, 3),
            },
        )

        return LoadedModel(
            pyfunc_model=pyfunc_model,
            model_uri=self._settings.model_uri,
            model_version=self._settings.model_version,
            registry_name=self._settings.model_registry_name,
            loaded_at=datetime.now(timezone.utc),
            load_duration_seconds=round(duration, 3),
        )
