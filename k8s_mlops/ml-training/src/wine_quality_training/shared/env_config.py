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

    Raises RuntimeError immediately if any required variable is absent so
    that the Kubernetes Job fails fast with a clear error rather than
    producing incorrect output silently.

    ENTERPRISE EMPHASIS: Failing fast on missing configuration prevents the
    job from reaching the model-training phase and writing a corrupt artifact
    to the artifact store — a mistake that is expensive to detect downstream.
    """
    _require_env_vars(
        required=[
            "ARTIFACT_STORE_ROOT",
            "PIPELINE_CONFIG_PATH",
        ]
    )

    return TrainingPipelineEnvConfig(
        artifact_store_root=Path(os.environ["ARTIFACT_STORE_ROOT"]),
        pipeline_config_path=Path(os.environ["PIPELINE_CONFIG_PATH"]),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
        optuna_n_trials=int(os.environ.get("OPTUNA_N_TRIALS", "50")),
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
