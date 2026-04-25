"""
Unit tests for pipeline run configuration overrides.

These tests prove that a teammate can request a new training run with different
runtime parameters without editing Python code or the base YAML configuration.
"""

from pathlib import Path

from wine_quality_training.pipeline.pipeline_run_config import (
    load_pipeline_run_config,
)


def test_optuna_trials_can_be_overridden_by_runtime_settings(tmp_path):
    config_path = _write_minimal_config(tmp_path)

    config = load_pipeline_run_config(config_path, optuna_n_trials_override=7)

    assert config.optuna.n_trials == 7


def test_random_seed_can_be_overridden_by_runtime_settings(tmp_path):
    config_path = _write_minimal_config(tmp_path)

    config = load_pipeline_run_config(config_path, random_seed_override=123)

    assert config.random_seed == 123


def test_experiment_name_can_be_overridden_by_runtime_settings(tmp_path):
    config_path = _write_minimal_config(tmp_path)

    config = load_pipeline_run_config(
        config_path,
        experiment_name_override="wine-quality-recovery-run",
    )

    assert config.experiment_name == "wine-quality-recovery-run"


def _write_minimal_config(tmp_path: Path) -> Path:
    config_path = tmp_path / "training_pipeline.yaml"
    config_path.write_text(
        """
experiment_name: wine-quality-classifier
artifact_store_root: artifacts
model_families:
  - random_forest
test_size: 0.2
random_seed: 42
cv_folds: 3
optuna:
  n_trials: 3
  timeout_seconds: 60
  direction: maximize
  metric: balanced_accuracy
""".lstrip()
    )
    return config_path
