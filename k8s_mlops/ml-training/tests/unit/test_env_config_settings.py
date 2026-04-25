"""
Unit tests for central Pydantic runtime settings.

These tests prove that local env files, environment variable overrides, and
validation all flow through one settings object instead of scattered os.getenv
calls.
"""

from pathlib import Path

import pytest

from wine_quality_training.shared.env_config import load_training_env_config


def test_settings_load_from_explicit_env_file(tmp_path, monkeypatch):
    config_file = _write_pipeline_config(tmp_path)
    env_file = tmp_path / "local-mlflow.env"
    env_file.write_text(
        f"""
PIPELINE_CONFIG_PATH={config_file.as_posix()}
ARTIFACT_STORE_ROOT={tmp_path.as_posix()}/artifacts
TRAINING_RUNTIME_MODE=mlflow_candidate_review
MLFLOW_TRACKING_URI=http://127.0.0.1:5000
OPTUNA_N_TRIALS=5
TRAINING_TRIGGERED_BY=shubham
TRAINING_RUN_REASON=manual candidate run from test
""".lstrip()
    )

    monkeypatch.delenv("TRAINING_RUNTIME_MODE", raising=False)
    settings = load_training_env_config(env_file=env_file)

    assert settings.training_runtime_mode == "mlflow_candidate_review"
    assert settings.publishes_to_mlflow is True
    assert settings.mlflow_tracking_uri == "http://127.0.0.1:5000"
    assert settings.optuna_n_trials == 5
    assert settings.training_triggered_by == "shubham"


def test_environment_variable_overrides_env_file(tmp_path, monkeypatch):
    config_file = _write_pipeline_config(tmp_path)
    env_file = tmp_path / "local-mlflow.env"
    env_file.write_text(
        f"""
PIPELINE_CONFIG_PATH={config_file.as_posix()}
OPTUNA_N_TRIALS=5
""".lstrip()
    )
    monkeypatch.setenv("OPTUNA_N_TRIALS", "9")

    settings = load_training_env_config(env_file=env_file)

    assert settings.optuna_n_trials == 9


def test_default_runtime_mode_is_local_artifact_only(tmp_path, monkeypatch):
    config_file = _write_pipeline_config(tmp_path)
    env_file = tmp_path / "local-only.env"
    env_file.write_text(f"PIPELINE_CONFIG_PATH={config_file.as_posix()}\n")
    monkeypatch.delenv("TRAINING_RUNTIME_MODE", raising=False)

    settings = load_training_env_config(env_file=env_file)

    assert settings.training_runtime_mode == "local_artifact_only"
    assert settings.publishes_to_mlflow is False


def test_missing_pipeline_config_path_raises_actionable_error(tmp_path):
    env_file = tmp_path / "bad.env"
    env_file.write_text("PIPELINE_CONFIG_PATH=does-not-exist.yaml\n")

    with pytest.raises(RuntimeError, match="Pipeline config not found"):
        load_training_env_config(env_file=env_file)


def _write_pipeline_config(tmp_path: Path) -> Path:
    config_file = tmp_path / "training_pipeline.yaml"
    config_file.write_text(
        """
experiment_name: wine-quality-cultivar-classification-v1
artifact_store_root: artifacts
model_families:
  - random_forest
test_size: 0.2
random_seed: 42
cv_folds: 3
optuna:
  n_trials: 2
  timeout_seconds: 30
  direction: maximize
  metric: balanced_accuracy
""".lstrip()
    )
    return config_file
