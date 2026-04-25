"""
Module: mlflow_experiment_manager
Purpose: Make MLflow experiment selection resilient when teammates or platform
         administrators have soft-deleted an experiment in the tracking server.
Inputs:  MLflow tracking URI, desired experiment name, and a policy that says
         whether deleted experiments should be restored automatically or treated
         as a hard failure.
Outputs: A typed summary of the active MLflow experiment that the pipeline can
         safely use for Optuna trial evidence and final candidate publication.
Tradeoffs: The default policy restores a soft-deleted experiment to preserve
           lineage continuity. In some enterprises, restoring may be forbidden
           by governance policy, so a strict fail-fast mode is also supported.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from wine_quality_training.shared.structured_logger import get_pipeline_logger

MlflowDeletedExperimentPolicy = Literal["restore", "fail"]

logger = get_pipeline_logger(__name__, phase="mlflow_experiment_resolution")


@dataclass(frozen=True)
class MlflowExperimentResolution:
    """
    Summary of how the pipeline resolved an MLflow experiment name.

    Purpose:
        Gives the caller both the experiment identity and the action taken to
        make it usable.
    Parameters:
        experiment_name:  Active experiment name used by the current run.
        experiment_id:    MLflow experiment identifier.
        resolution_action:
            `existing_active` when the experiment already existed,
            `created_new` when MLflow created it on demand,
            `restored_deleted` when a soft-deleted experiment was brought back.
    Return value:
        This dataclass is returned by ensure_mlflow_experiment_ready().
    Failure behavior:
        The resolver raises RuntimeError when policy is `fail` and the desired
        experiment exists only in the deleted state.
    Enterprise equivalent:
        Shared ML platforms often guard tracking resources centrally. This
        helper is the application-side safety net that keeps one cleanup action
        from breaking every teammate's training run.
    """

    experiment_name: str
    experiment_id: str
    resolution_action: str


def ensure_mlflow_experiment_ready(
    *,
    tracking_uri: str,
    experiment_name: str,
    deleted_experiment_policy: MlflowDeletedExperimentPolicy,
) -> MlflowExperimentResolution:
    """
    Ensure the requested MLflow experiment exists in the active lifecycle state.

    Purpose:
        MLflow refuses to activate an experiment name that exists only in the
        deleted state. This helper makes that lifecycle check explicit and
        either restores the deleted experiment or fails with an actionable
        message, depending on policy.
    Parameters:
        tracking_uri:               MLflow Tracking server URI.
        experiment_name:            Desired experiment name for this run.
        deleted_experiment_policy:  `restore` or `fail`.
    Return value:
        MlflowExperimentResolution for the active experiment.
    Failure behavior:
        Raises RuntimeError when the experiment is deleted and policy is `fail`,
        or when MLflow cannot produce an active experiment after restore/create.
    Enterprise equivalent:
        This mirrors the kind of preflight guard a platform SDK would perform
        before a training workflow starts emitting governed tracking records.
    """

    import mlflow
    from mlflow.entities import ViewType
    from mlflow.tracking import MlflowClient

    mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient(tracking_uri=tracking_uri)

    active_experiment = client.get_experiment_by_name(experiment_name)
    if active_experiment is not None:
        # IMPORTANT: mlflow.set_experiment() must always be called even when
        # the experiment already exists. MLflow tracks the "active experiment"
        # as process-level global state. If we return here without calling it,
        # mlflow.start_run() will fall back to the "Default" experiment — which
        # is the silent failure that causes all runs to land in the wrong bucket.
        # This is the most common source of the "why are my runs in Default?"
        # problem when a pipeline is run more than once or after a server restart.
        mlflow.set_experiment(experiment_name)
        return MlflowExperimentResolution(
            experiment_name=active_experiment.name,
            experiment_id=active_experiment.experiment_id,
            resolution_action="existing_active",
        )

    deleted_experiment = _find_deleted_experiment_by_name(
        client=client,
        experiment_name=experiment_name,
        view_type=ViewType.DELETED_ONLY,
    )
    if deleted_experiment is not None:
        if deleted_experiment_policy == "fail":
            raise RuntimeError(
                "MLflow experiment "
                f"'{experiment_name}' exists in the deleted state. "
                "Restore it in MLflow, or choose a different experiment name "
                "with MLFLOW_EXPERIMENT_NAME."
            )

        client.restore_experiment(deleted_experiment.experiment_id)
        restored_experiment = client.get_experiment_by_name(experiment_name)
        if restored_experiment is None:
            raise RuntimeError(
                "MLflow reported that the deleted experiment was restored, but "
                f"'{experiment_name}' still could not be resolved as active."
            )

        logger.warning(
            "MLflow experiment was soft-deleted and has been restored automatically",
            extra={
                "experiment_name": restored_experiment.name,
                "experiment_id": restored_experiment.experiment_id,
            },
        )
        # Activate the restored experiment in MLflow's process-level global
        # state so subsequent start_run() calls land in the correct experiment.
        mlflow.set_experiment(experiment_name)
        return MlflowExperimentResolution(
            experiment_name=restored_experiment.name,
            experiment_id=restored_experiment.experiment_id,
            resolution_action="restored_deleted",
        )

    mlflow.set_experiment(experiment_name)
    created_experiment = client.get_experiment_by_name(experiment_name)
    if created_experiment is None:
        raise RuntimeError(
            "MLflow did not return an active experiment after creation for "
            f"'{experiment_name}'."
        )

    return MlflowExperimentResolution(
        experiment_name=created_experiment.name,
        experiment_id=created_experiment.experiment_id,
        resolution_action="created_new",
    )


def _find_deleted_experiment_by_name(*, client, experiment_name: str, view_type):
    """
    Search deleted experiments by exact name.

    MLflow's get_experiment_by_name() only returns active experiments, so a
    second lookup across deleted experiments is required when a name appears to
    be missing.
    """

    matching_experiments = client.search_experiments(view_type=view_type)
    for experiment in matching_experiments:
        if experiment.name == experiment_name:
            return experiment
    return None
