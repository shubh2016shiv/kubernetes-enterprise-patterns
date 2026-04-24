"""
Model evaluation phase: compute classification metrics on the held-out test split.

This phase runs after training and before artifact registration. Its output —
a structured EvaluationResult — is persisted as metrics.json inside the
versioned artifact directory.

The test split is used here for the first and only time. It was never seen
during hyperparameter search (cross-validation used only training data), so
the reported metrics are unbiased estimates of generalisation performance.

ENTERPRISE EMPHASIS: In enterprise MLOps, evaluation results must be compared
against a promotion threshold before a model version is registered as a
candidate for deployment. Storing metrics.json alongside the model artifact
makes this gate auditable: any pipeline step, CI job, or human reviewer can
check the numbers without re-running training.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.pipeline import Pipeline

from wine_quality_training.feature_engineering.build_wine_features import WineTrainingDataSplit
from wine_quality_training.training.wine_quality_model_trainer import TrainingResult
from wine_quality_training.shared.structured_logger import get_pipeline_logger

logger = get_pipeline_logger(__name__, phase="model_evaluation")


@dataclass
class ModelEvaluationResult:
    """
    All classification metrics computed on the held-out test split.

    Persisted as metrics.json in the versioned artifact directory.
    Used by the model registry phase to decide whether this run meets the
    promotion threshold defined in training_pipeline.yaml.
    """

    accuracy: float
    balanced_accuracy: float
    macro_f1: float
    weighted_f1: float
    macro_precision: float
    macro_recall: float
    per_class_f1: dict[str, float]
    per_class_precision: dict[str, float]
    per_class_recall: dict[str, float]
    confusion_matrix: list[list[int]]
    classification_report_text: str
    n_test_samples: int
    target_class_names: list[str]
    evaluation_passed_threshold: bool
    promotion_threshold_balanced_accuracy: float


def evaluate_wine_quality_model(
    training_result: TrainingResult,
    data_split: WineTrainingDataSplit,
    promotion_threshold: float = 0.85,
) -> ModelEvaluationResult:
    """
    Evaluate the fitted pipeline on the held-out test split.

    Args:
        training_result: Output of the training phase (fitted Pipeline + metadata).
        data_split:      The same WineTrainingDataSplit used in training (X_test, y_test).
        promotion_threshold: Minimum balanced_accuracy required to pass evaluation.

    Returns:
        ModelEvaluationResult with all metrics and a pass/fail flag.
    """
    logger.info(
        "Evaluating model on held-out test split",
        extra={"n_test_samples": len(data_split.X_test)},
    )

    pipeline = training_result.fitted_pipeline
    X_test = data_split.X_test
    y_test = data_split.y_test
    class_names = data_split.feature_schema.target_class_names

    y_pred = pipeline.predict(X_test)

    accuracy = float(accuracy_score(y_test, y_pred))
    balanced_acc = float(balanced_accuracy_score(y_test, y_pred))
    macro_f1 = float(f1_score(y_test, y_pred, average="macro", zero_division=0))
    weighted_f1 = float(f1_score(y_test, y_pred, average="weighted", zero_division=0))
    macro_precision = float(precision_score(y_test, y_pred, average="macro", zero_division=0))
    macro_recall = float(recall_score(y_test, y_pred, average="macro", zero_division=0))

    per_class_f1 = _per_class_metric(f1_score, y_test, y_pred, class_names)
    per_class_precision = _per_class_metric(precision_score, y_test, y_pred, class_names)
    per_class_recall = _per_class_metric(recall_score, y_test, y_pred, class_names)

    cm = confusion_matrix(y_test, y_pred).tolist()
    report_text = classification_report(y_test, y_pred, target_names=class_names, zero_division=0)

    evaluation_passed = balanced_acc >= promotion_threshold

    result = ModelEvaluationResult(
        accuracy=round(accuracy, 4),
        balanced_accuracy=round(balanced_acc, 4),
        macro_f1=round(macro_f1, 4),
        weighted_f1=round(weighted_f1, 4),
        macro_precision=round(macro_precision, 4),
        macro_recall=round(macro_recall, 4),
        per_class_f1=per_class_f1,
        per_class_precision=per_class_precision,
        per_class_recall=per_class_recall,
        confusion_matrix=cm,
        classification_report_text=report_text,
        n_test_samples=len(X_test),
        target_class_names=class_names,
        evaluation_passed_threshold=evaluation_passed,
        promotion_threshold_balanced_accuracy=promotion_threshold,
    )

    _log_evaluation_summary(result)
    return result


def _per_class_metric(metric_fn, y_true, y_pred, class_names: list[str]) -> dict[str, float]:
    scores = metric_fn(y_true, y_pred, average=None, zero_division=0)
    return {class_names[i]: round(float(scores[i]), 4) for i in range(len(class_names))}


def _log_evaluation_summary(result: ModelEvaluationResult) -> None:
    status = "PASSED" if result.evaluation_passed_threshold else "FAILED"
    logger.info(
        f"Evaluation {status} (threshold={result.promotion_threshold_balanced_accuracy})",
        extra={
            "accuracy": result.accuracy,
            "balanced_accuracy": result.balanced_accuracy,
            "macro_f1": result.macro_f1,
            "evaluation_passed": result.evaluation_passed_threshold,
        },
    )
    logger.info("\n" + result.classification_report_text)
