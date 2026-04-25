"""
Unit tests for MLflow experiment lifecycle recovery.

These tests use small fakes instead of a live MLflow server so the suite can
prove deleted-experiment handling deterministically and quickly.
"""

from types import SimpleNamespace

import pytest

from wine_quality_training.shared.mlflow_experiment_manager import (
    ensure_mlflow_experiment_ready,
)


class FakeMlflowModule:
    """Minimal fake for the top-level mlflow module used by the resolver."""

    def __init__(self):
        self.tracking_uri = None
        self.set_experiment_calls: list[str] = []

    def set_tracking_uri(self, tracking_uri: str) -> None:
        self.tracking_uri = tracking_uri

    def set_experiment(self, experiment_name: str) -> None:
        self.set_experiment_calls.append(experiment_name)


class FakeMlflowClient:
    """Small in-memory stand-in for MlflowClient lifecycle methods."""

    experiments_by_name: dict[str, object] = {}
    deleted_experiments_by_name: dict[str, object] = {}
    restored_experiment_ids: list[str] = []

    def __init__(self, tracking_uri: str):
        self.tracking_uri = tracking_uri

    @classmethod
    def reset(cls) -> None:
        cls.experiments_by_name = {}
        cls.deleted_experiments_by_name = {}
        cls.restored_experiment_ids = []

    def get_experiment_by_name(self, experiment_name: str):
        return self.experiments_by_name.get(experiment_name)

    def search_experiments(self, view_type):
        return list(self.deleted_experiments_by_name.values())

    def restore_experiment(self, experiment_id: str) -> None:
        self.restored_experiment_ids.append(experiment_id)
        for name, experiment in list(self.deleted_experiments_by_name.items()):
            if experiment.experiment_id == experiment_id:
                self.experiments_by_name[name] = experiment
                del self.deleted_experiments_by_name[name]
                return
        raise AssertionError(f"Unexpected experiment_id restore request: {experiment_id}")


@pytest.fixture(autouse=True)
def patch_fake_mlflow(monkeypatch):
    fake_mlflow = FakeMlflowModule()
    fake_view_type = SimpleNamespace(DELETED_ONLY="DELETED_ONLY")

    FakeMlflowClient.reset()
    monkeypatch.setitem(__import__("sys").modules, "mlflow", fake_mlflow)
    monkeypatch.setitem(
        __import__("sys").modules,
        "mlflow.entities",
        SimpleNamespace(ViewType=fake_view_type),
    )
    monkeypatch.setitem(
        __import__("sys").modules,
        "mlflow.tracking",
        SimpleNamespace(MlflowClient=FakeMlflowClient),
    )
    return fake_mlflow


def test_deleted_experiment_is_restored_when_policy_is_restore():
    deleted = SimpleNamespace(
        name="wine-quality-cultivar-classification-v1",
        experiment_id="42",
    )
    FakeMlflowClient.deleted_experiments_by_name[deleted.name] = deleted

    resolution = ensure_mlflow_experiment_ready(
        tracking_uri="http://127.0.0.1:5000",
        experiment_name=deleted.name,
        deleted_experiment_policy="restore",
    )

    assert resolution.experiment_name == deleted.name
    assert resolution.experiment_id == "42"
    assert resolution.resolution_action == "restored_deleted"
    assert FakeMlflowClient.restored_experiment_ids == ["42"]


def test_deleted_experiment_raises_actionable_error_when_policy_is_fail():
    deleted = SimpleNamespace(
        name="wine-quality-cultivar-classification-v1",
        experiment_id="42",
    )
    FakeMlflowClient.deleted_experiments_by_name[deleted.name] = deleted

    with pytest.raises(RuntimeError, match="exists in the deleted state"):
        ensure_mlflow_experiment_ready(
            tracking_uri="http://127.0.0.1:5000",
            experiment_name=deleted.name,
            deleted_experiment_policy="fail",
        )
