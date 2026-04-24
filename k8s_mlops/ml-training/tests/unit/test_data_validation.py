"""
Unit tests for the data validation phase.

Tests cover the core contract: the validator must accept the expected wine
dataset structure and must reject datasets that violate schema requirements.
"""

import numpy as np
import pandas as pd
import pytest

from wine_quality_training.data_ingestion.load_wine_dataset import (
    RawWineDataset,
    WINE_FEATURE_NAMES,
    load_wine_dataset,
)
from wine_quality_training.data_validation.validate_training_schema import (
    DataValidationError,
    validate_wine_training_schema,
)


@pytest.fixture
def valid_dataset() -> RawWineDataset:
    return load_wine_dataset()


def test_valid_dataset_passes_validation(valid_dataset):
    report = validate_wine_training_schema(valid_dataset)
    assert report.validation_passed is True
    assert report.failure_reasons == []


def test_report_carries_correct_sample_count(valid_dataset):
    report = validate_wine_training_schema(valid_dataset)
    assert report.n_samples == 178


def test_report_carries_three_classes(valid_dataset):
    report = validate_wine_training_schema(valid_dataset)
    assert len(report.class_distribution) == 3


def test_missing_feature_column_raises_validation_error(valid_dataset):
    truncated_features = valid_dataset.features.drop(columns=["alcohol"])
    bad_dataset = RawWineDataset(
        features=truncated_features,
        targets=valid_dataset.targets,
        feature_names=valid_dataset.feature_names,
        target_class_names=valid_dataset.target_class_names,
        dataset_content_hash=valid_dataset.dataset_content_hash,
        n_samples=valid_dataset.n_samples,
        n_features=truncated_features.shape[1],
    )
    with pytest.raises(DataValidationError, match="Missing expected feature columns"):
        validate_wine_training_schema(bad_dataset)


def test_missing_values_in_features_raises_validation_error(valid_dataset):
    features_with_nulls = valid_dataset.features.copy()
    features_with_nulls.loc[0, "alcohol"] = np.nan
    bad_dataset = RawWineDataset(
        features=features_with_nulls,
        targets=valid_dataset.targets,
        feature_names=valid_dataset.feature_names,
        target_class_names=valid_dataset.target_class_names,
        dataset_content_hash=valid_dataset.dataset_content_hash,
        n_samples=valid_dataset.n_samples,
        n_features=valid_dataset.n_features,
    )
    with pytest.raises(DataValidationError, match="Missing values"):
        validate_wine_training_schema(bad_dataset)


def test_wrong_number_of_classes_raises_validation_error(valid_dataset):
    targets_two_class = valid_dataset.targets.copy()
    targets_two_class[targets_two_class == 2] = 1
    bad_dataset = RawWineDataset(
        features=valid_dataset.features,
        targets=targets_two_class,
        feature_names=valid_dataset.feature_names,
        target_class_names=["class_0", "class_1"],
        dataset_content_hash=valid_dataset.dataset_content_hash,
        n_samples=valid_dataset.n_samples,
        n_features=valid_dataset.n_features,
    )
    with pytest.raises(DataValidationError):
        validate_wine_training_schema(bad_dataset)
