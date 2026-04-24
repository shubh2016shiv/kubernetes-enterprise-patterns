"""
Unit tests for the feature engineering phase.

Validates that the stratified split preserves class proportions, produces
the expected sizes, and that the feature schema carries correct metadata.
"""

import pytest

from wine_quality_training.data_ingestion.load_wine_dataset import load_wine_dataset
from wine_quality_training.data_ingestion.load_wine_dataset import WINE_FEATURE_NAMES
from wine_quality_training.feature_engineering.build_wine_features import (
    build_wine_training_features,
)


@pytest.fixture(scope="module")
def data_split():
    dataset = load_wine_dataset()
    return build_wine_training_features(dataset, test_size=0.2, random_seed=42)


def test_split_sizes_sum_to_total(data_split):
    total = len(data_split.X_train) + len(data_split.X_test)
    assert total == 178


def test_test_size_is_approximately_20_percent(data_split):
    test_fraction = len(data_split.X_test) / 178
    assert 0.18 <= test_fraction <= 0.22


def test_feature_names_match_expected(data_split):
    assert list(data_split.X_train.columns) == WINE_FEATURE_NAMES


def test_schema_feature_names_match_dataframe(data_split):
    assert data_split.feature_schema.feature_names == list(data_split.X_train.columns)


def test_schema_carries_three_target_classes(data_split):
    assert len(data_split.feature_schema.target_class_names) == 3


def test_feature_statistics_cover_all_features(data_split):
    schema = data_split.feature_schema
    assert set(schema.feature_statistics.keys()) == set(WINE_FEATURE_NAMES)


def test_feature_statistics_have_expected_keys(data_split):
    first_col_stats = next(iter(data_split.feature_schema.feature_statistics.values()))
    assert {"mean", "std", "min", "max", "p25", "p75"} == set(first_col_stats.keys())


def test_stratified_split_preserves_all_classes_in_test(data_split):
    test_classes = set(data_split.y_test.unique())
    assert test_classes == {0, 1, 2}


def test_y_train_and_X_train_lengths_match(data_split):
    assert len(data_split.X_train) == len(data_split.y_train)


def test_y_test_and_X_test_lengths_match(data_split):
    assert len(data_split.X_test) == len(data_split.y_test)


def test_reproducibility_with_same_seed():
    dataset = load_wine_dataset()
    split_a = build_wine_training_features(dataset, random_seed=99)
    split_b = build_wine_training_features(dataset, random_seed=99)
    assert list(split_a.y_train) == list(split_b.y_train)
