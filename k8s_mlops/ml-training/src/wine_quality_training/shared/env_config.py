"""
Module: env_config
Purpose: Central typed runtime settings for the ML training pipeline.
Inputs:  Environment variables, optional dotenv-style env files, and defaults
         suitable for local WSL2 development.
Outputs: A validated TrainingPipelineEnvConfig object consumed by the pipeline
         orchestrator.
Tradeoffs: Local learners may use configs/local-mlflow.env for convenience.
           Enterprise Kubernetes uses ConfigMaps and Secrets to inject the same
           keys as environment variables without baking environment-specific
           values into the container image.
"""

from __future__ import annotations

# Standard library: os is used only to locate an optional env-file override.
# Runtime values themselves are parsed and validated by Pydantic Settings.
import os
from pathlib import Path
from typing import Literal

# Third-party: Pydantic Settings provides the enterprise-friendly pattern for
# typed configuration loaded from environment variables, dotenv files, or
# secrets directories. It keeps config parsing out of business logic.
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

TrainingRuntimeMode = Literal["local_artifact_only", "mlflow_candidate_review"]


class TrainingPipelineEnvConfig(BaseSettings):
    """
    Central runtime settings consumed by the training pipeline.

    Purpose:
        Provide one authoritative place for runtime values such as artifact
        paths, MLflow settings, and team-trigger metadata.
    Parameters:
        Values are loaded from process environment variables first, then from
        optional env files such as configs/local-mlflow.env, then from defaults.
    Return value:
        A validated Pydantic Settings object.
    Failure behavior:
        Invalid types fail during settings construction. Missing config files
        are checked by load_training_env_config() so the error message can teach
        the learner what to fix.
    Enterprise equivalent:
        In Kubernetes, non-secret values come from ConfigMaps and secret values
        come from Secrets. The Python code still reads the same central settings
        object, which preserves environment parity.
    """

    model_config = SettingsConfigDict(
        env_file=(".env", "configs/local-mlflow.env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    artifact_store_root: Path = Field(
        default=Path("artifacts"),
        description="Root directory or mounted path where versioned artifacts are written.",
    )
    pipeline_config_path: Path = Field(
        default=Path("configs/training_pipeline.yaml"),
        description="YAML pipeline config path. In Kubernetes this comes from a ConfigMap mount.",
    )
    log_level: str = Field(
        default="INFO",
        description="Structured logging level for the training process.",
    )
    optuna_n_trials: int = Field(
        default=60,
        ge=1,
        description="Number of Optuna hyperparameter-search trials for this run.",
    )
    random_seed: int = Field(
        default=42,
        description="Seed for reproducible train/test split and model search.",
    )
    training_runtime_mode: TrainingRuntimeMode = Field(
        default="local_artifact_only",
        description=(
            "Explicit runtime mode. local_artifact_only writes versioned local "
            "artifacts only. mlflow_candidate_review logs Optuna trials and "
            "publishes the final passing model as an MLflow candidate."
        ),
    )
    mlflow_tracking_uri: str = Field(
        default="sqlite:///mlflow.db",
        description="MLflow Tracking server URI or local SQLite backend URI.",
    )
    mlflow_registered_model_name: str = Field(
        default="wine-quality-classifier",
        description="Stable MLflow Model Registry name used for candidate publication.",
    )
    mlflow_candidate_alias: str = Field(
        default="candidate",
        description="Mutable MLflow alias assigned to the latest reviewable model version.",
    )
    training_run_reason: str = Field(
        default="local training run",
        description="Human-readable reason this training run was requested.",
    )
    training_triggered_by: str = Field(
        default="local-user",
        description="Person, CI system, or Kubernetes controller that triggered the run.",
    )

    @field_validator("log_level")
    @classmethod
    def normalize_log_level(cls, value: str) -> str:
        """Normalize log level values so env files can use lowercase safely."""

        return value.upper()

    @property
    def publishes_to_mlflow(self) -> bool:
        """
        Return whether this runtime mode should publish experiment evidence.

        Purpose:
            Gives the pipeline readable intent without checking low-level MLflow
            fields directly.
        Parameters:
            None.
        Return value:
            True for mlflow_candidate_review, false for local_artifact_only.
        Failure behavior:
            None; invalid modes are rejected by Pydantic before this property is
            accessed.
        Enterprise equivalent:
            Platform teams usually encode this as an environment or workflow
            mode, not as a developer-chosen command-line flag.
        """

        return self.training_runtime_mode == "mlflow_candidate_review"


def load_training_env_config(env_file: Path | None = None) -> TrainingPipelineEnvConfig:
    """
    Load and validate training runtime settings.

    For local development, sensible defaults are provided:
      ARTIFACT_STORE_ROOT   -> artifacts/
      PIPELINE_CONFIG_PATH  -> configs/training_pipeline.yaml

    For local MLflow candidate runs, copy:
      configs/local-mlflow.env.example -> configs/local-mlflow.env

    In Kubernetes, these are overridden by the Job spec env injection from
    ConfigMap/Secret values, which take precedence over defaults.

    ENTERPRISE EMPHASIS: Failing fast on invalid configuration prevents the
    job from reaching the model-training phase and writing a corrupt artifact
    to the artifact store - a mistake that is expensive to detect downstream.
    """

    resolved_env_file = env_file or _env_file_from_runtime_override()
    settings = (
        TrainingPipelineEnvConfig(_env_file=resolved_env_file)
        if resolved_env_file
        else TrainingPipelineEnvConfig()
    )

    if not settings.pipeline_config_path.exists():
        raise RuntimeError(
            f"Pipeline config not found at '{settings.pipeline_config_path}'. "
            "Set PIPELINE_CONFIG_PATH to the correct path or run from the "
            f"ml-training directory where '{settings.pipeline_config_path}' exists."
        )

    return settings


def _env_file_from_runtime_override() -> Path | None:
    """
    Resolve an optional env-file path from TRAINING_ENV_FILE.

    Purpose:
        Lets a learner or CI job choose an explicit config file without changing
        Python code.
    Parameters:
        None.
    Return value:
        Path to the env file when TRAINING_ENV_FILE is set, otherwise None.
    Failure behavior:
        Raises RuntimeError if TRAINING_ENV_FILE points to a missing file.
    Enterprise equivalent:
        Kubernetes normally injects environment variables directly. An explicit
        env file is mostly a local-lab convenience.
    """

    env_file = os.environ.get("TRAINING_ENV_FILE")
    if not env_file:
        return None

    env_file_path = Path(env_file)
    if not env_file_path.exists():
        raise RuntimeError(
            f"TRAINING_ENV_FILE points to '{env_file_path}', but that file does not exist."
        )
    return env_file_path
