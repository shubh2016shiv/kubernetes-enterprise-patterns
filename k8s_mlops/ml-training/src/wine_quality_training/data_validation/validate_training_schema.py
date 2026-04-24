"""
Data validation phase: enforce schema and statistical contracts on the raw dataset.

This phase runs before any feature engineering. It fails loudly if the dataset
does not meet the expected structural and statistical contract so that downstream
phases never process corrupt or drifted data.

In a Kubernetes-based pipeline, this phase maps to its own Job that runs before
the feature engineering Job. If this Job fails, the pipeline halts and no
compute is wasted on training a model from bad data.

ENTERPRISE EMPHASIS: Data validation is the first line of defence against silent
training failures caused by upstream data contract changes. A schema check that
takes two seconds can prevent a six-hour training run from producing a
wrong-but-plausible model.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from wine_quality_training.data_ingestion.load_wine_dataset import (
    WINE_FEATURE_NAMES,
    RawWineDataset,
    TARGET_COLUMN,
)
from wine_quality_training.shared.structured_logger import get_pipeline_logger

logger = get_pipeline_logger(__name__, phase="data_validation")

EXPECTED_N_FEATURES: int = 13
EXPECTED_N_CLASSES: int = 3
MIN_SAMPLES_PER_CLASS: int = 30

FEATURE_DTYPE_EXPECTATIONS: dict[str, str] = {
    name: "float64" for name in WINE_FEATURE_NAMES
}

FEATURE_VALUE_BOUNDS: dict[str, tuple[float, float]] = {
    "alcohol": (10.0, 15.5),
    "malic_acid": (0.5, 6.0),
    "ash": (1.0, 4.0),
    "alcalinity_of_ash": (10.0, 35.0),
    "magnesium": (60.0, 165.0),
    "total_phenols": (0.5, 4.0),
    "flavanoids": (0.0, 6.0),
    "nonflavanoid_phenols": (0.0, 0.70),
    "proanthocyanins": (0.2, 4.0),
    "color_intensity": (1.0, 14.0),
    "hue": (0.3, 2.0),
    "od280_od315_of_diluted_wines": (1.0, 4.5),
    "proline": (200.0, 2000.0),
}


@dataclass
class DataValidationReport:
    """
    Structured report produced after running all validation checks.

    Passed downstream as evidence that validation completed successfully.
    Persisted as part of the run manifest in the artifact store.
    """

    n_samples: int
    n_features: int
    class_distribution: dict[int, int]
    missing_value_counts: dict[str, int]
    out_of_bounds_counts: dict[str, int]
    validation_passed: bool
    failure_reasons: list[str] = field(default_factory=list)


def validate_wine_training_schema(dataset: RawWineDataset) -> DataValidationReport:
    """
    Run all structural and statistical validation checks on the raw dataset.

    Checks performed:
      1. Feature count matches expected schema
      2. All expected feature columns are present
      3. Feature dtypes are numeric (float64)
      4. No missing values in features or targets
      5. Target has exactly the expected number of classes
      6. Each class has at least MIN_SAMPLES_PER_CLASS samples
      7. Feature values fall within expected physical bounds

    Args:
        dataset: RawWineDataset produced by the ingestion phase.

    Returns:
        DataValidationReport. If validation_passed is False the pipeline
        must halt before proceeding to feature engineering.

    Raises:
        DataValidationError: when any mandatory check fails.
    """
    logger.info("Starting training dataset validation")

    failures: list[str] = []
    features = dataset.features
    targets = dataset.targets

    _check_feature_count(features, failures)
    _check_feature_columns_present(features, failures)
    _check_feature_dtypes(features, failures)
    missing_value_counts = _check_missing_values(features, targets, failures)
    _check_target_classes(targets, dataset.target_class_names, failures)
    class_distribution = _check_class_distribution(targets, failures)
    out_of_bounds_counts = _check_feature_value_bounds(features, failures)

    validation_passed = len(failures) == 0

    report = DataValidationReport(
        n_samples=dataset.n_samples,
        n_features=dataset.n_features,
        class_distribution=class_distribution,
        missing_value_counts=missing_value_counts,
        out_of_bounds_counts=out_of_bounds_counts,
        validation_passed=validation_passed,
        failure_reasons=failures,
    )

    if not validation_passed:
        logger.error(
            "Dataset validation FAILED",
            extra={"failure_count": len(failures), "failures": failures},
        )
        raise DataValidationError(
            f"Dataset validation failed with {len(failures)} error(s): {failures}"
        )

    logger.info(
        "Dataset validation passed",
        extra={
            "n_samples": report.n_samples,
            "class_distribution": report.class_distribution,
            "out_of_bounds_counts": report.out_of_bounds_counts,
        },
    )
    return report


class DataValidationError(Exception):
    """Raised when the training dataset fails a mandatory validation check."""


def _check_feature_count(features: pd.DataFrame, failures: list[str]) -> None:
    if features.shape[1] != EXPECTED_N_FEATURES:
        failures.append(
            f"Expected {EXPECTED_N_FEATURES} features, found {features.shape[1]}"
        )


def _check_feature_columns_present(features: pd.DataFrame, failures: list[str]) -> None:
    missing_cols = set(WINE_FEATURE_NAMES) - set(features.columns)
    if missing_cols:
        failures.append(f"Missing expected feature columns: {sorted(missing_cols)}")


def _check_feature_dtypes(features: pd.DataFrame, failures: list[str]) -> None:
    for col in features.columns:
        if col not in FEATURE_DTYPE_EXPECTATIONS:
            continue
        if not pd.api.types.is_float_dtype(features[col]):
            failures.append(
                f"Feature '{col}' expected float dtype, got {features[col].dtype}"
            )


def _check_missing_values(
    features: pd.DataFrame, targets: pd.Series, failures: list[str]
) -> dict[str, int]:
    missing_counts: dict[str, int] = features.isnull().sum().to_dict()
    cols_with_missing = {k: v for k, v in missing_counts.items() if v > 0}
    if cols_with_missing:
        failures.append(f"Missing values found in features: {cols_with_missing}")
    if targets.isnull().sum() > 0:
        failures.append(f"Missing values found in target column: {targets.isnull().sum()}")
    return missing_counts


def _check_target_classes(
    targets: pd.Series, class_names: list[str], failures: list[str]
) -> None:
    n_unique = targets.nunique()
    if n_unique != EXPECTED_N_CLASSES:
        failures.append(
            f"Expected {EXPECTED_N_CLASSES} target classes, found {n_unique}"
        )
    if len(class_names) != EXPECTED_N_CLASSES:
        failures.append(
            f"Expected {EXPECTED_N_CLASSES} class name labels, found {len(class_names)}"
        )


def _check_class_distribution(
    targets: pd.Series, failures: list[str]
) -> dict[int, int]:
    distribution: dict[int, int] = targets.value_counts().sort_index().to_dict()
    for cls, count in distribution.items():
        if count < MIN_SAMPLES_PER_CLASS:
            failures.append(
                f"Class {cls} has only {count} samples (minimum: {MIN_SAMPLES_PER_CLASS})"
            )
    return distribution


def _check_feature_value_bounds(
    features: pd.DataFrame, failures: list[str]
) -> dict[str, int]:
    out_of_bounds: dict[str, int] = {}
    for col, (low, high) in FEATURE_VALUE_BOUNDS.items():
        if col not in features.columns:
            continue
        n_violations = int(((features[col] < low) | (features[col] > high)).sum())
        out_of_bounds[col] = n_violations
        if n_violations > 0:
            logger.warning(
                f"Feature '{col}' has {n_violations} value(s) outside expected bounds "
                f"[{low}, {high}] — may indicate data drift"
            )
    return out_of_bounds
