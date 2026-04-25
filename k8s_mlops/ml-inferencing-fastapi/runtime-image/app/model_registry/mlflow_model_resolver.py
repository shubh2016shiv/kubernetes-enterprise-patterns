"""
Module: mlflow_model_resolver
Purpose: Resolve an MLflow model alias to an immutable version number and URI.
Inputs:  MLflow tracking URI, registered model name, alias name.
Outputs: A ResolvedModelReference dataclass with version number and model URI.
Tradeoffs: This module is used by the release bridge scripts, not by the FastAPI
           runtime. FastAPI receives an already-resolved MODEL_URI from its
           environment and never resolves aliases at serving time.
           This separation is the core architectural rule of this platform:
           the platform resolves; FastAPI serves.
"""

from __future__ import annotations

# Standard library: dataclasses provide a typed, immutable result container.
from dataclasses import dataclass

# Local: logging follows the same structured format used everywhere in this app.
from app.core.logging_config import get_logger

logger = get_logger(__name__)


@dataclass(frozen=True)
class ResolvedModelReference:
    """
    Purpose:
        Carry the result of resolving a moving alias to a fixed version.
    Fields:
        registry_name:  Registered model name in MLflow.
        alias:          The alias that was resolved (e.g., champion).
        version:        The immutable version number the alias pointed to.
        model_uri:      The full immutable MLflow model URI ready for loading.
    Enterprise equivalent:
        In a CI/CD pipeline, this object is the artifact that gets serialized
        into pipeline variables and passed to the deployment job. It represents
        the deployment decision: "we are rolling out version N."
    """

    registry_name: str
    alias: str
    version: str
    model_uri: str


def resolve_model_alias(
    *,
    tracking_uri: str,
    registry_name: str,
    alias: str,
) -> ResolvedModelReference:
    """
    Purpose:
        Call the MLflow Model Registry to resolve a named alias to an
        immutable version number and construct the deployment-safe model URI.

        This function is intentionally NOT called inside FastAPI at serving time.
        It is designed for the release bridge scripts that run before a rollout.
        FastAPI receives the already-resolved MODEL_URI through its environment.

    Parameters:
        tracking_uri:   MLflow Tracking Server base URI.
        registry_name:  Registered model name, e.g. wine-quality-classifier-prod.
        alias:          Human-friendly alias to resolve, e.g. champion.

    Return value:
        ResolvedModelReference with the immutable version and model URI.

    Failure behavior:
        Raises MlflowException if the alias does not exist or the MLflow server
        is unreachable. The release bridge script catches this and exits with a
        non-zero code so CI/CD marks the release step as failed.

    Enterprise equivalent:
        In production, this call would go to the MLflow server over TLS with
        service account authentication. The resolved version and URI would be
        persisted as pipeline artifacts or GitHub Actions outputs before being
        used to update Kubernetes configuration.

    ENTERPRISE EMPHASIS: Alias resolution happens exactly once per release, not
    once per inference request. If a pod resolved the alias on every request, a
    manager moving champion between two requests would cause the same pod to
    return inconsistent predictions. Resolution at release time is the correct
    pattern.
    """
    # Import mlflow here rather than at module top level so the release bridge
    # can import this module without requiring mlflow in all test environments.
    import mlflow
    from mlflow.tracking import MlflowClient

    mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient(tracking_uri=tracking_uri)

    logger.info(
        "Resolving MLflow model alias",
        extra={
            "tracking_uri": tracking_uri,
            "registry_name": registry_name,
            "alias": alias,
        },
    )

    model_version = client.get_model_version_by_alias(
        name=registry_name,
        alias=alias,
    )

    version_number = str(model_version.version)
    immutable_uri = f"models:/{registry_name}/{version_number}"

    result = ResolvedModelReference(
        registry_name=registry_name,
        alias=alias,
        version=version_number,
        model_uri=immutable_uri,
    )

    logger.info(
        "Alias resolved to immutable version",
        extra={
            "registry_name": registry_name,
            "alias": alias,
            "resolved_version": version_number,
            "model_uri": immutable_uri,
        },
    )

    return result


def verify_model_uri_exists(
    *,
    tracking_uri: str,
    model_uri: str,
) -> bool:
    """
    Purpose:
        Verify that the model artifact referenced by model_uri exists and is
        accessible via the MLflow Tracking Server. Used as a preflight check
        before rolling out a new deployment configuration.

    Parameters:
        tracking_uri: MLflow Tracking Server base URI.
        model_uri:    Immutable model URI, e.g. models:/wine-quality-classifier-prod/1.

    Return value:
        True if the artifact is accessible, False if it cannot be reached.

    Failure behavior:
        Logs the error and returns False. The caller decides whether to abort
        or continue. The release bridge treats False as a release gate failure.

    Enterprise equivalent:
        Production release pipelines include artifact verification gates to
        prevent deploying a MODEL_URI that would cause all pods to fail on
        startup because the artifact was deleted or the storage was misconfigured.
    """
    import mlflow

    mlflow.set_tracking_uri(tracking_uri)

    logger.info(
        "Verifying model artifact accessibility",
        extra={"model_uri": model_uri, "tracking_uri": tracking_uri},
    )

    try:
        # pyfunc.load_model() with no predict call verifies the artifact is
        # downloadable. It is cheap to call in a short-lived release script.
        mlflow.pyfunc.load_model(model_uri)
        logger.info("Model artifact verified successfully", extra={"model_uri": model_uri})
        return True
    except Exception as exc:  # noqa: BLE001
        logger.error(
            "Model artifact verification failed",
            extra={"model_uri": model_uri, "error": str(exc)},
        )
        return False
