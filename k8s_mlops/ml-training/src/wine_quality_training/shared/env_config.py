"""
Environment-based configuration loader for the training pipeline.

All runtime values are injected through environment variables so that the
same container image can run in local, staging, and production Kubernetes
environments without being rebuilt.

ENTERPRISE EMPHASIS: Externalising configuration into environment variables
(populated from ConfigMaps and Secrets) is the Kubernetes-native approach to
environment parity. Hardcoded paths or URIs create invisible differences
between environments and break CI/CD reproducibility.
"""

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class TrainingPipelineEnvConfig:
    """
    All environment values consumed by the training pipeline.

    In Kubernetes the values come from:
      - Non-sensitive fields  -> env vars injected from a ConfigMap
      - Sensitive fields      -> env vars injected from a Secret
    """

    artifact_store_root: Path
    pipeline_config_path: Path
    log_level: str
    optuna_n_trials: int
    random_seed: int


def load_training_env_config() -> TrainingPipelineEnvConfig:
    """
    Read and validate required environment variables.

    For local development, sensible defaults are provided:
      ARTIFACT_STORE_ROOT   → artifacts/
      PIPELINE_CONFIG_PATH  → configs/training_pipeline.yaml

    In Kubernetes, these are overridden by the Job spec env injection from
    ConfigMap/Secret values, which take precedence over defaults.

    ENTERPRISE EMPHASIS: Failing fast on invalid configuration prevents the
    job from reaching the model-training phase and writing a corrupt artifact
    to the artifact store — a mistake that is expensive to detect downstream.
    """
    artifact_store_root = os.environ.get(
        "ARTIFACT_STORE_ROOT",
        "artifacts"  # local development default
    )
    pipeline_config_path = os.environ.get(
        "PIPELINE_CONFIG_PATH",
        "configs/training_pipeline.yaml"  # local development default
    )

    artifact_store_path = Path(artifact_store_root)
    config_path = Path(pipeline_config_path)

    if not config_path.exists():
        raise RuntimeError(
            f"Pipeline config not found at '{config_path}'. "
            f"Set PIPELINE_CONFIG_PATH to the correct path or run from the "
            f"ml-training directory where '{pipeline_config_path}' exists."
        )

    return TrainingPipelineEnvConfig(
        artifact_store_root=artifact_store_path,
        pipeline_config_path=config_path,
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
        optuna_n_trials=int(os.environ.get("OPTUNA_N_TRIALS", "60")),
        random_seed=int(os.environ.get("RANDOM_SEED", "42")),
    )


def _require_env_vars(required: list[str]) -> None:
    missing = [name for name in required if not os.getenv(name)]
    if missing:
        raise RuntimeError(
            f"Missing required environment variables: {missing}. "
            "In Kubernetes, these must be set via ConfigMap env injection "
            "in the Job spec's env or envFrom fields."
        )
