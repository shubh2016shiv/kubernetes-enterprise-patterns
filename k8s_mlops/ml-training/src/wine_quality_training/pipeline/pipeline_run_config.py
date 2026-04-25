"""
Pipeline run configuration loader.

Configuration is read from a YAML file whose path is injected through the
PIPELINE_CONFIG_PATH environment variable. Values in the file can be
overridden at runtime by environment variables, which is the pattern used
when a Kubernetes ConfigMap supplies base configuration and a Job spec
overrides specific fields per run.

ENTERPRISE EMPHASIS: This module describes the run specification for the whole
training pipeline, not only the model-fitting step. Keeping it under
wine_quality_training.pipeline makes the boundary clear:
  - pipeline_run_config.py decides what this run should do
  - wine_quality_model_trainer.py executes the model-training phase
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import yaml


@dataclass(frozen=True)
class OptunaSearchConfig:
    """Search configuration passed to the Optuna study."""

    n_trials: int
    timeout_seconds: int | None
    direction: str
    metric: str


@dataclass(frozen=True)
class PipelineRunConfig:
    """
    Full resolved run specification for one training pipeline execution.

    Produced by load_pipeline_run_config() and passed through all
    training-phase modules so no module reads files or env vars directly.
    """

    experiment_name: str
    model_family_names: list[str]
    test_size: float
    random_seed: int
    cv_folds: int
    optuna: OptunaSearchConfig
    artifact_store_root: Path


def load_pipeline_run_config(
    config_path: Path,
    *,
    optuna_n_trials_override: int | None = None,
    random_seed_override: int | None = None,
) -> PipelineRunConfig:
    """
    Parse the YAML config file and return a typed, immutable config object.

    Args:
        config_path: Absolute path to training_pipeline.yaml.
        optuna_n_trials_override: Runtime override from central Pydantic
                                  settings. Used by CI, Kubernetes Jobs, and
                                  local env files.
        random_seed_override: Runtime override from central Pydantic settings.

    Returns:
        PipelineRunConfig populated from file values.

    Raises:
        FileNotFoundError: if the config file does not exist at config_path.
        KeyError: if a required config key is missing from the YAML.
    """
    if not config_path.exists():
        raise FileNotFoundError(
            f"Training pipeline config not found at '{config_path}'. "
            "Ensure PIPELINE_CONFIG_PATH env var points to the mounted ConfigMap file."
        )

    with config_path.open("r") as fh:
        raw: dict = yaml.safe_load(fh)

    optuna_raw = raw["optuna"]
    optuna = OptunaSearchConfig(
        # ENTERPRISE EMPHASIS: A teammate can manually request a larger or
        # smaller search through TrainingPipelineEnvConfig. The versioned
        # run_manifest.json will still record the resulting trial count.
        n_trials=int(
            optuna_n_trials_override
            if optuna_n_trials_override is not None
            else optuna_raw["n_trials"]
        ),
        timeout_seconds=optuna_raw.get("timeout_seconds"),
        direction=optuna_raw.get("direction", "maximize"),
        metric=optuna_raw.get("metric", "balanced_accuracy"),
    )

    return PipelineRunConfig(
        experiment_name=raw["experiment_name"],
        model_family_names=raw["model_families"],
        test_size=float(raw.get("test_size", 0.2)),
        random_seed=int(
            random_seed_override
            if random_seed_override is not None
            else raw.get("random_seed", 42)
        ),
        cv_folds=int(raw.get("cv_folds", 5)),
        optuna=optuna,
        artifact_store_root=Path(raw["artifact_store_root"]),
    )
