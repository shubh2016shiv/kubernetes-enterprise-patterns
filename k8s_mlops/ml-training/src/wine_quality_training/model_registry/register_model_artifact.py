"""
Model artifact registration phase: persist all training outputs into a versioned
directory in the artifact store.

Files written per version:
  model.joblib           — the fitted sklearn Pipeline (scaler + classifier)
  metrics.json           — evaluation metrics from the test split
  training_config.json   — hyperparameters chosen by Optuna + pipeline config
  feature_schema.json    — feature names, statistics, target classes
  run_manifest.json      — full lineage record (version, timestamp, data hash, git sha)

The artifact store root is a local filesystem directory in this project.
In production it would be an S3 bucket, Azure Blob container, or GCS bucket,
with the same directory structure mapped to object key prefixes.

ENTERPRISE EMPHASIS: Every file written here is a traceable unit. The
run_manifest.json ties together the dataset hash, code version, configuration,
and evaluation outcome into a single auditability record. Without this, a
question like "which training run produced the model currently in production?"
requires expensive log archaeology.
"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

import joblib

from wine_quality_training.evaluation.evaluate_wine_quality_model import ModelEvaluationResult
from wine_quality_training.feature_engineering.build_wine_features import (
    FeatureSchema,
    WineTrainingDataSplit,
)
from wine_quality_training.model_registry.artifact_version_resolver import (
    resolve_next_artifact_version,
)
from wine_quality_training.training.wine_quality_model_trainer import TrainingResult
from wine_quality_training.shared.structured_logger import get_pipeline_logger

logger = get_pipeline_logger(__name__, phase="artifact_registration")

MODEL_NAME = "wine_quality_classifier"


@dataclass
class RegisteredArtifact:
    """
    Reference to a successfully written artifact version.

    Returned to the pipeline orchestrator after registration completes.
    """

    model_name: str
    version: str
    artifact_directory: Path
    model_artifact_path: Path
    run_manifest_path: Path
    evaluation_passed: bool


def register_model_artifact(
    training_result: TrainingResult,
    evaluation_result: ModelEvaluationResult,
    data_split: WineTrainingDataSplit,
    artifact_store_root: Path,
    dataset_content_hash: str,
    experiment_name: str,
) -> RegisteredArtifact:
    """
    Write all training outputs into a new versioned artifact directory.

    Args:
        training_result:      Fitted pipeline and training metadata.
        evaluation_result:    Test-split metrics and promotion flag.
        data_split:           Feature schema and split sizes.
        artifact_store_root:  Root of the local artifact store.
        dataset_content_hash: SHA-256 of the training dataset (from ingestion phase).
        experiment_name:      Experiment identifier from the pipeline config.

    Returns:
        RegisteredArtifact pointing to the written directory.
    """
    version = resolve_next_artifact_version(artifact_store_root, MODEL_NAME)
    artifact_dir = artifact_store_root / MODEL_NAME / version
    artifact_dir.mkdir(parents=True, exist_ok=False)

    logger.info(
        "Registering model artifact",
        extra={"model_name": MODEL_NAME, "version": version, "artifact_dir": str(artifact_dir)},
    )

    model_path = _write_model_artifact(artifact_dir, training_result)
    _write_metrics(artifact_dir, evaluation_result)
    _write_training_config(artifact_dir, training_result, experiment_name)
    _write_feature_schema(artifact_dir, data_split.feature_schema)
    manifest_path = _write_run_manifest(
        artifact_dir=artifact_dir,
        version=version,
        model_name=MODEL_NAME,
        experiment_name=experiment_name,
        training_result=training_result,
        evaluation_result=evaluation_result,
        feature_schema=data_split.feature_schema,
        dataset_content_hash=dataset_content_hash,
        model_artifact_path=model_path,
    )

    registered = RegisteredArtifact(
        model_name=MODEL_NAME,
        version=version,
        artifact_directory=artifact_dir,
        model_artifact_path=model_path,
        run_manifest_path=manifest_path,
        evaluation_passed=evaluation_result.evaluation_passed_threshold,
    )

    logger.info(
        "Artifact registration complete",
        extra={
            "version": version,
            "artifact_dir": str(artifact_dir),
            "evaluation_passed": registered.evaluation_passed,
        },
    )
    return registered


def _write_model_artifact(artifact_dir: Path, training_result: TrainingResult) -> Path:
    model_path = artifact_dir / "model.joblib"
    joblib.dump(training_result.fitted_pipeline, model_path, compress=3)
    logger.info(f"Written model.joblib ({model_path.stat().st_size // 1024} KB)")
    return model_path


def _write_metrics(artifact_dir: Path, evaluation_result: ModelEvaluationResult) -> None:
    metrics_payload = {
        "accuracy": evaluation_result.accuracy,
        "balanced_accuracy": evaluation_result.balanced_accuracy,
        "macro_f1": evaluation_result.macro_f1,
        "weighted_f1": evaluation_result.weighted_f1,
        "macro_precision": evaluation_result.macro_precision,
        "macro_recall": evaluation_result.macro_recall,
        "per_class_f1": evaluation_result.per_class_f1,
        "per_class_precision": evaluation_result.per_class_precision,
        "per_class_recall": evaluation_result.per_class_recall,
        "confusion_matrix": evaluation_result.confusion_matrix,
        "n_test_samples": evaluation_result.n_test_samples,
        "target_class_names": evaluation_result.target_class_names,
        "evaluation_passed_threshold": evaluation_result.evaluation_passed_threshold,
        "promotion_threshold_balanced_accuracy": evaluation_result.promotion_threshold_balanced_accuracy,
    }
    _write_json(artifact_dir / "metrics.json", metrics_payload)


def _write_training_config(
    artifact_dir: Path,
    training_result: TrainingResult,
    experiment_name: str,
) -> None:
    config_payload = {
        "experiment_name": experiment_name,
        "model_family": training_result.best_model_family,
        "hyperparameters": training_result.best_hyperparameters,
        "cv_metric": training_result.cv_metric,
        "best_cv_score": round(training_result.best_cv_score, 4),
        "n_trials_completed": training_result.n_trials_completed,
        "n_training_samples": training_result.n_training_samples,
    }
    _write_json(artifact_dir / "training_config.json", config_payload)


def _write_feature_schema(artifact_dir: Path, schema: FeatureSchema) -> None:
    schema_payload = {
        "feature_names": schema.feature_names,
        "feature_statistics": schema.feature_statistics,
        "target_column": schema.target_column,
        "target_class_names": schema.target_class_names,
        "train_size": schema.train_size,
        "test_size": schema.test_size,
        "stratified_split": schema.stratified_split,
    }
    _write_json(artifact_dir / "feature_schema.json", schema_payload)


def _write_run_manifest(
    artifact_dir: Path,
    version: str,
    model_name: str,
    experiment_name: str,
    training_result: TrainingResult,
    evaluation_result: ModelEvaluationResult,
    feature_schema: FeatureSchema,
    dataset_content_hash: str,
    model_artifact_path: Path,
) -> Path:
    model_artifact_sha256 = _file_sha256(model_artifact_path)
    git_sha = _resolve_git_sha()

    manifest = {
        "schema_version": "1.0",
        "model_name": model_name,
        "version": version,
        "experiment_name": experiment_name,
        "registered_at_utc": datetime.now(timezone.utc).isoformat(),
        "python_version": platform.python_version(),
        "platform": platform.system(),
        "git_commit_sha": git_sha,
        "dataset_content_hash": dataset_content_hash,
        "model_artifact_sha256": model_artifact_sha256,
        "model_family": training_result.best_model_family,
        "n_training_samples": training_result.n_training_samples,
        "n_test_samples": evaluation_result.n_test_samples,
        "n_features": len(feature_schema.feature_names),
        "cv_metric": training_result.cv_metric,
        "best_cv_score": round(training_result.best_cv_score, 4),
        "balanced_accuracy_test": evaluation_result.balanced_accuracy,
        "evaluation_passed": evaluation_result.evaluation_passed_threshold,
        "promotion_threshold": evaluation_result.promotion_threshold_balanced_accuracy,
    }
    manifest_path = artifact_dir / "run_manifest.json"
    _write_json(manifest_path, manifest)
    return manifest_path


def _write_json(path: Path, payload: dict) -> None:
    with path.open("w") as fh:
        json.dump(payload, fh, indent=2, default=str)


def _file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _resolve_git_sha() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True, timeout=5,
        )
        return result.stdout.strip()
    except Exception:
        return "unknown"
