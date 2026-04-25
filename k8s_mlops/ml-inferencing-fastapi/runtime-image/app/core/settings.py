"""
Module: settings
Purpose: Typed runtime configuration for the wine quality inference API.
Inputs:  Environment variables injected by Kubernetes ConfigMap and Secret.
         The ConfigMap carries non-sensitive values such as MODEL_URI and
         MLFLOW_TRACKING_URI. A Secret would carry any credential (not required
         for this local lab because the MLflow server has no authentication).
Outputs: A validated InferenceSettings object used by every other module.
Tradeoffs: Local pre-container runs may read runtime-image/.env so developers
           can validate model loading without a long list of shell exports. In
           Kubernetes, the same setting names are injected from ConfigMaps and
           Secrets into the pod's environment at startup. External Secrets
           Operator or AWS Secrets Manager can supply secret values without
           baking them into the manifest.
"""

from __future__ import annotations

# Standard library: lru_cache ensures settings are created once per process.
# os and Path support the optional INFERENCE_ENV_FILE override for local tests.
from functools import lru_cache
import os
from pathlib import Path

# Third-party: Pydantic Settings provides typed, validated configuration from
# environment variables. The Field() alias maps Python attribute names to the
# exact environment variable names Kubernetes supplies.
# Enterprise: Pydantic Settings makes the config contract explicit. A new
# engineer can read this file and know exactly what env vars the pod requires.
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class InferenceSettings(BaseSettings):
    """
    Purpose:
        Represent all runtime settings required by the inference API. Every
        field that FastAPI, the model loader, the health service, and the
        prediction service need comes from this single typed object.
    Parameters:
        Values are loaded by Pydantic from environment variables and, for local
        pre-container development, runtime-image/.env. In Kubernetes, the same
        variable names are injected through ConfigMap envFrom and Secret env
        entries.
    Return value:
        A validated settings object. Pydantic raises a validation error at
        startup if a required field is missing or has the wrong type. The pod
        will fail to start and Kubernetes will show the error in pod Events.
    Failure behavior:
        Required fields without defaults raise ValidationError on startup.
        Kubernetes restarts the pod and surfaces the error in:
          kubectl describe pod <pod-name> -n ml-inference
    Enterprise equivalent:
        The same Pydantic Settings pattern works when values come from Helm
        chart values, Kustomize overlays, ArgoCD ApplicationSets, or a
        platform-provided self-service config portal. The Python code does
        not care how the environment variables were set — only that they exist
        and have the correct types.

    ENTERPRISE EMPHASIS: All configuration lives here. No other module in this
    application should call os.getenv() or os.environ[]. Centralizing config
    means one grep of this file shows every knob the pod exposes, which is
    essential for security reviews, on-call runbooks, and deployment audits.
    """

    model_config = SettingsConfigDict(
        # Local pre-container workflow: when you run uvicorn from runtime-image/,
        # Pydantic reads .env so you do not need a fragile pile of export commands.
        #
        # Kubernetes workflow: the Deployment still injects these same names from
        # ConfigMap and Secret objects. Real environment variables override .env
        # values, so cluster behavior stays controlled by Kubernetes.
        #
        # ENTERPRISE EMPHASIS: local and Kubernetes paths must share one typed
        # config contract. The anti-pattern is having one config style for
        # developers and a different hidden style in the container.
        env_file=".env",
        env_file_encoding="utf-8",
        # Ignore extra environment variables the pod may receive (e.g., Kubernetes
        # downward API vars or service account token paths).
        extra="ignore",
    )

    # ─────────────────────────────────────────────────────────────────────────
    # Model reference — set by the CI/CD release bridge, not by the developer.
    # These values identify exactly which model version this pod is serving.
    # ─────────────────────────────────────────────────────────────────────────

    model_uri: str = Field(
        alias="MODEL_URI",
        description=(
            "Immutable MLflow model URI for this deployment. "
            "Example: models:/wine-quality-classifier-prod/1. "
            "Set by the CI/CD release bridge after resolving the @champion alias. "
            "FastAPI loads this URI at startup and serves it for the pod's lifetime. "
            "NEVER point this at a moving alias such as @champion."
        ),
    )

    model_registry_name: str = Field(
        alias="MODEL_REGISTRY_NAME",
        description=(
            "MLflow registered model name. "
            "Example: wine-quality-classifier-prod. "
            "Used in health check responses and prediction logs for traceability."
        ),
    )

    model_version: str = Field(
        alias="MODEL_VERSION",
        description=(
            "Resolved immutable model version number. "
            "Example: 1. "
            "Set alongside MODEL_URI by the release bridge. "
            "Used in logs, health responses, and audit records."
        ),
    )

    mlflow_tracking_uri: str = Field(
        alias="MLFLOW_TRACKING_URI",
        description=(
            "MLflow Tracking Server URI the pod uses to download the model artifact. "
            "Local lab: http://host.docker.internal:5000 (WSL2 host). "
            "Enterprise: https://mlflow.internal.company.com."
        ),
    )

    # ─────────────────────────────────────────────────────────────────────────
    # Application identity — non-sensitive, set in ConfigMap.
    # ─────────────────────────────────────────────────────────────────────────

    app_name: str = Field(
        default="wine-quality-inference-api",
        alias="APP_NAME",
        description="Service name for logging and health responses.",
    )

    app_environment: str = Field(
        default="local-kind",
        alias="APP_ENVIRONMENT",
        description=(
            "Deployment environment label. "
            "LOCAL SHORTCUT: local-kind. "
            "ENTERPRISE EQUIVALENT: staging, production, eu-west-1-production."
        ),
    )

    app_version: str = Field(
        default="1.0.0",
        alias="APP_VERSION",
        description="Inference API application version for OpenAPI and metadata endpoint.",
    )

    log_level: str = Field(
        default="INFO",
        alias="LOG_LEVEL",
        description="Structured logging level. Accepted values: DEBUG, INFO, WARNING, ERROR.",
    )

    # ─────────────────────────────────────────────────────────────────────────
    # Kubernetes downward API — injected by the deployment spec fieldRef.
    # These give logs and health checks pod-level identity without hard-coding.
    # ─────────────────────────────────────────────────────────────────────────

    pod_name: str = Field(
        default="unknown-pod",
        alias="POD_NAME",
        description="Injected by Kubernetes downward API. Useful for log correlation.",
    )

    pod_namespace: str = Field(
        default="unknown-namespace",
        alias="POD_NAMESPACE",
        description="Injected by Kubernetes downward API. Confirms namespace in health checks.",
    )

    node_name: str = Field(
        default="unknown-node",
        alias="NODE_NAME",
        description="Injected by Kubernetes downward API. Useful for node-level debugging.",
    )

    @field_validator("log_level")
    @classmethod
    def normalize_log_level(cls, value: str) -> str:
        """Normalize log level so operators can use either uppercase or lowercase."""
        return value.upper()

    @property
    def served_model_identifier(self) -> str:
        """
        Purpose:
            Return a human-readable string that unambiguously identifies the
            model version currently loaded by this pod.
        Return value:
            String like "wine-quality-classifier-prod/1" for use in logs and
            health check responses.
        Enterprise equivalent:
            Production observability systems use this identifier to correlate
            prediction requests with model versions in their lineage tracking.
        """
        return f"{self.model_registry_name}/{self.model_version}"


@lru_cache(maxsize=1)
def get_inference_settings() -> InferenceSettings:
    """
    Purpose:
        Provide one shared InferenceSettings instance across the application.
        lru_cache(maxsize=1) ensures Pydantic constructs the settings object
        only once per process, regardless of how many request handlers call it.
    Return value:
        Validated InferenceSettings object.
    Failure behavior:
        Raises pydantic.ValidationError if required fields are missing. The pod
        will fail to start. Kubernetes will restart it and surface the error in
        pod Events and logs.
    Enterprise equivalent:
        Central settings construction via dependency injection keeps all service
        code free from scattered os.getenv() calls and makes configuration
        auditable from one file.
    """
    return load_inference_settings()


def load_inference_settings(env_file: Path | None = None) -> InferenceSettings:
    """
    Purpose:
        Build the typed inference settings object from one central location.
    Parameters:
        env_file: Optional local .env path used by tests or developer tooling.
            When omitted, Pydantic reads runtime-image/.env if the current
            working directory is runtime-image/.
    Return value:
        Validated InferenceSettings object.
    Failure behavior:
        Raises pydantic.ValidationError if required config is missing or
        malformed. This is intentional fail-fast behavior.
    Enterprise equivalent:
        A production platform may render these values from Helm, Kustomize,
        ArgoCD, or a deployment portal. The application still consumes the same
        validated settings object, so config drift is easier to audit.

    ENTERPRISE EMPHASIS: this helper exists so local uv runs, tests, and the
    container startup path all use the same settings class instead of scattered
    os.getenv() calls.
    """
    selected_env_file = env_file or _env_file_from_runtime_override()
    if selected_env_file is None:
        return InferenceSettings()

    return InferenceSettings(_env_file=selected_env_file)


def _env_file_from_runtime_override() -> Path | None:
    """
    Purpose:
        Let a developer or test point at a specific local environment file with
        INFERENCE_ENV_FILE without changing application code.
    Parameters:
        None.
    Return value:
        Path to the requested local environment file, or None when the default
        .env lookup should be used.
    Failure behavior:
        Missing files are allowed to fail through Pydantic's normal missing
        required-field validation rather than being silently ignored.
    Enterprise equivalent:
        CI jobs often provide an explicit config file path for repeatable test
        runs. Production pods normally omit this variable and receive config
        from Kubernetes instead.
    """
    override_path = os.getenv("INFERENCE_ENV_FILE")
    if not override_path:
        return None

    return Path(override_path)
