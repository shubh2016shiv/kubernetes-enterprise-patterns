"""
Unit tests for MLflow trial tracking configuration objects.

These tests keep the experiment-tracking integration explicit without requiring
a live MLflow server during the normal unit suite.
"""

from wine_quality_training.training.wine_quality_model_trainer import (
    MlflowTrialTrackingConfig,
)


def test_mlflow_trial_tracking_config_carries_review_metadata():
    config = MlflowTrialTrackingConfig(
        tracking_uri="http://127.0.0.1:5000",
        experiment_name="wine_quality_classifier",
        run_group_id="training-abc123",
        run_reason="manual candidate run",
        triggered_by="shubham",
    )

    assert config.tracking_uri == "http://127.0.0.1:5000"
    assert config.experiment_name == "wine_quality_classifier"
    assert config.run_group_id == "training-abc123"
    assert config.run_reason == "manual candidate run"
    assert config.triggered_by == "shubham"
