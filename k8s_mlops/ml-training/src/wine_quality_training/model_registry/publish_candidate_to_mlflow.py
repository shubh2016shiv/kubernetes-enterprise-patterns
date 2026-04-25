"""
Module: publish_candidate_to_mlflow
Purpose: Publish a completed training run to MLflow Tracking and Model Registry
         as a reviewable candidate model version.
Inputs:  The local RegisteredArtifact bundle plus in-memory training and
         evaluation results from the current pipeline run.
Outputs: An MLflow run, a registered model version, model version tags, and
         optionally the mutable `candidate` alias.
Tradeoffs: The local lab can use a file-based MLflow store for learning. A real
           enterprise setup uses a shared tracking server backed by PostgreSQL
           or MySQL and an object store such as Amazon S3, Google Cloud Storage,
           or Azure Blob Storage.
"""

from __future__ import annotations

# Standard library: dataclasses for typed return values and pathlib for artifact
# paths that work both on local WSL2 and inside a Linux container.
from dataclasses import dataclass
from pathlib import Path

# Project modules: these dataclasses carry the pipeline outputs from earlier
# phases without forcing this module to reread JSON files from disk.
from wine_quality_training.evaluation.evaluate_wine_quality_model import (
    ModelEvaluationResult,
)
from wine_quality_training.model_registry.register_model_artifact import (
    RegisteredArtifact,
)
from wine_quality_training.shared.structured_logger import get_pipeline_logger
from wine_quality_training.training.wine_quality_model_trainer import TrainingResult

logger = get_pipeline_logger(__name__, phase="mlflow_candidate_publishing")


@dataclass(frozen=True)
class MlflowCandidatePublication:
    """
    Result of publishing one artifact bundle to MLflow.

    Purpose:
        Gives the pipeline a small, typed summary of what MLflow accepted.
    Parameters:
        tracking_uri: MLflow Tracking server or local file-store URI.
        run_id:       MLflow run identifier for metrics, params, and artifacts.
        model_name:   Registered model name visible in the MLflow UI.
        version:      MLflow model registry version number.
        alias:        Alias assigned to this version, usually `candidate`.
    Return value:
        This dataclass is the return value.
    Failure behavior:
        The publisher raises an exception if MLflow is enabled but unavailable.
        That makes the pipeline fail loudly instead of silently losing lineage.
    Enterprise equivalent:
        In production, this object is what a downstream approval or deployment
        pipeline would persist as an auditable event.
    """

    tracking_uri: str
    run_id: str
    model_name: str
    version: str
    alias: str | None


def publish_candidate_to_mlflow(
    *,
    tracking_uri: str,
    experiment_name: str,
    registered_model_name: str,
    candidate_alias: str,
    run_reason: str,
    triggered_by: str,
    run_group_id: str,
    registered_artifact: RegisteredArtifact,
    training_result: TrainingResult,
    evaluation_result: ModelEvaluationResult,
) -> MlflowCandidatePublication:
    """
    Publish a completed local artifact bundle as an MLflow candidate.

    Purpose:
        Converts the repository's local versioned artifact bundle into an
        enterprise-style registry record that teammates can review in MLflow.
    Parameters:
        tracking_uri:           MLflow backend URI, for example
                                `http://mlflow.company.internal` or
                                `file:./mlruns` for the local lab.
        experiment_name:        MLflow experiment that groups trial evidence
                                and final candidate publication.
        registered_model_name:  Stable registry name, such as
                                `wine-quality-classifier`.
        candidate_alias:        Mutable alias that points to the newest
                                reviewable candidate.
        run_reason:             Human-readable reason supplied by the teammate
                                or workflow trigger.
        triggered_by:           Person or automation that requested this run.
        run_group_id:           Correlation ID shared with hyperparameter trial
                                runs logged earlier in the pipeline.
        registered_artifact:    Local artifact bundle written by Phase 6.
        training_result:        Best model and hyperparameter search metadata.
        evaluation_result:      Test metrics and promotion gate result.
    Return value:
        MlflowCandidatePublication with the MLflow run and model version.
    Failure behavior:
        Raises ImportError when MLflow is not installed, and lets MLflow client
        errors propagate when the tracking server is unreachable.
    Enterprise equivalent:
        This is the training-side handoff to the model governance workflow. It
        does not deploy the model; it only makes a candidate available for
        review, audit, and later approval.
    """

    # Import MLflow only when publishing is enabled. This keeps unit tests and
    # local pipeline runs lightweight unless the learner explicitly uses the
    # tracking/registry path.
    import mlflow
    import mlflow.sklearn
    from mlflow.tracking import MlflowClient

    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(experiment_name)

    logger.info(
        "Publishing model candidate to MLflow",
        extra={
            "tracking_uri": tracking_uri,
            "registered_model_name": registered_model_name,
            "local_artifact_version": registered_artifact.version,
        },
    )

    with mlflow.start_run(
        run_name=f"{registered_artifact.model_name}-{registered_artifact.version}"
    ) as run:
        mlflow.log_params(
            {
                "local_artifact_version": registered_artifact.version,
                "model_family": training_result.best_model_family,
                "cv_metric": training_result.cv_metric,
                "n_trials_completed": training_result.n_trials_completed,
                "n_training_samples": training_result.n_training_samples,
                "run_reason": run_reason,
                "triggered_by": triggered_by,
                "run_group_id": run_group_id,
            }
        )
        mlflow.set_tags(
            {
                "run_type": "candidate_model",
                "run_group_id": run_group_id,
                "review_role": "registry_candidate",
            }
        )
        mlflow.log_params(training_result.best_hyperparameters)
        mlflow.log_metrics(
            {
                "accuracy": evaluation_result.accuracy,
                "balanced_accuracy": evaluation_result.balanced_accuracy,
                "macro_f1": evaluation_result.macro_f1,
                "weighted_f1": evaluation_result.weighted_f1,
                "best_cv_score": training_result.best_cv_score,
            }
        )

        # ENTERPRISE EMPHASIS: The full artifact bundle is logged in addition
        # to the MLflow model object. Reviewers need metrics.json,
        # feature_schema.json, and run_manifest.json to understand what changed,
        # not only the serialized sklearn model.
        mlflow.log_artifacts(
            str(registered_artifact.artifact_directory),
            artifact_path="artifact_bundle",
        )

        model_info = mlflow.sklearn.log_model(
            sk_model=training_result.fitted_pipeline,
            name="model",
            registered_model_name=registered_model_name,
        )

    client = MlflowClient(tracking_uri=tracking_uri)
    model_version = _resolve_registered_model_version(
        client=client,
        registered_model_name=registered_model_name,
        run_id=run.info.run_id,
        model_info=model_info,
    )

    review_status = (
        "pending_human_review"
        if evaluation_result.evaluation_passed_threshold
        else "failed_automatic_metric_gate"
    )
    _set_model_version_tags(
        client=client,
        registered_model_name=registered_model_name,
        model_version=model_version,
        registered_artifact=registered_artifact,
        review_status=review_status,
        run_reason=run_reason,
        triggered_by=triggered_by,
        run_group_id=run_group_id,
    )

    assigned_alias = None
    if evaluation_result.evaluation_passed_threshold:
        # The `candidate` alias is a moving pointer to the newest version that
        # deserves review. It is not production approval. A later human approval
        # step can move `champion` to the chosen version.
        client.set_registered_model_alias(
            name=registered_model_name,
            alias=candidate_alias,
            version=model_version,
        )
        assigned_alias = candidate_alias

    logger.info(
        "MLflow candidate publication complete",
        extra={
            "run_id": run.info.run_id,
            "registered_model_name": registered_model_name,
            "mlflow_model_version": model_version,
            "assigned_alias": assigned_alias,
        },
    )

    return MlflowCandidatePublication(
        tracking_uri=tracking_uri,
        run_id=run.info.run_id,
        model_name=registered_model_name,
        version=model_version,
        alias=assigned_alias,
    )


def _resolve_registered_model_version(
    *,
    client,
    registered_model_name: str,
    run_id: str,
    model_info,
) -> str:
    """
    Resolve the MLflow Model Registry version created for this run.

    Purpose:
        MLflow versions have changed their return objects across releases. This
        helper first uses the direct field when available, then falls back to
        searching registry versions by run_id.
    Parameters:
        client:                 MlflowClient instance.
        registered_model_name:  Registry model name.
        run_id:                 Current MLflow run ID.
        model_info:             Return value from mlflow.sklearn.log_model().
    Return value:
        The registry version number as a string.
    Failure behavior:
        Raises RuntimeError if no model version can be tied back to this run.
    Enterprise equivalent:
        This is the lineage link between an experiment run and the model version
        reviewers approve.
    """

    direct_version = getattr(model_info, "registered_model_version", None)
    if direct_version:
        return str(direct_version)

    matching_versions = client.search_model_versions(
        f"name = '{registered_model_name}' and run_id = '{run_id}'"
    )
    if not matching_versions:
        raise RuntimeError(
            "MLflow registered the model, but no model version could be "
            f"resolved for run_id={run_id} and name={registered_model_name}."
        )

    return str(matching_versions[0].version)


def _set_model_version_tags(
    *,
    client,
    registered_model_name: str,
    model_version: str,
    registered_artifact: RegisteredArtifact,
    review_status: str,
    run_reason: str,
    triggered_by: str,
    run_group_id: str,
) -> None:
    """
    Attach review and lineage metadata to the MLflow model version.

    Purpose:
        Makes the MLflow UI answer "why does this candidate exist?" without
        requiring the reviewer to open CI logs.
    Parameters:
        client:                 MlflowClient instance.
        registered_model_name:  Registry model name.
        model_version:          MLflow model version number.
        registered_artifact:    Local artifact bundle from the pipeline.
        review_status:          Human-readable status for approval workflow.
        run_reason:             Reason supplied by teammate or automation.
        triggered_by:           Person or system that requested the run.
        run_group_id:           Correlation ID shared with experiment runs.
    Return value:
        None.
    Failure behavior:
        MLflow client errors propagate to the caller.
    Enterprise equivalent:
        These tags are a lightweight stand-in for enterprise model governance
        metadata such as Jira ticket IDs, approver groups, and risk categories.
    """

    tags = {
        "review_status": review_status,
        "local_artifact_version": registered_artifact.version,
        "local_artifact_dir": _as_posix_path(registered_artifact.artifact_directory),
        "run_manifest_path": _as_posix_path(registered_artifact.run_manifest_path),
        "run_reason": run_reason,
        "triggered_by": triggered_by,
        "run_group_id": run_group_id,
    }
    for key, value in tags.items():
        client.set_model_version_tag(
            name=registered_model_name,
            version=model_version,
            key=key,
            value=str(value),
        )


def _as_posix_path(path: Path) -> str:
    """Return a path string that reads naturally in Linux-first docs and logs."""

    return path.as_posix()
