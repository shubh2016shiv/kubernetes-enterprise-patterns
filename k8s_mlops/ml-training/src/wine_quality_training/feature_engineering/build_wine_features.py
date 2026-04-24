"""
Feature engineering phase: produce the training-ready feature matrix and target vector.

This phase is responsible for:
  - Splitting the validated dataset into train and test partitions
  - Recording the feature schema (names, statistics) that the serving layer
    must replicate at inference time
  - Exposing the raw (unscaled) splits to the trainer, which owns scaling
    as part of its sklearn Pipeline

Scaling is intentionally NOT applied here. It is applied inside the sklearn
Pipeline in the training phase so that the scaler is fitted only on training
data and is serialised as part of the model artifact. This prevents data
leakage from test statistics into training.

ENTERPRISE EMPHASIS: The feature schema produced here (column names, dtypes,
expected value ranges) is what the inference API must enforce at prediction time.
If the serving layer receives a request with different feature names or order,
it must reject the request rather than silently serving a wrong prediction.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedShuffleSplit

from wine_quality_training.data_ingestion.load_wine_dataset import RawWineDataset
from wine_quality_training.shared.structured_logger import get_pipeline_logger

logger = get_pipeline_logger(__name__, phase="feature_engineering")


@dataclass(frozen=True)
class FeatureSchema:
    """
    Describes the contract between the training pipeline and the inference API.

    The inference API loads this schema at startup to validate incoming
    prediction requests before passing them to the model.

    ENTERPRISE EMPHASIS: A versioned feature schema is essential for detecting
    training-serving skew — the most common silent failure mode in production ML.
    """

    feature_names: list[str]
    feature_statistics: dict[str, dict[str, float]]
    target_column: str
    target_class_names: list[str]
    train_size: int
    test_size: int
    stratified_split: bool


@dataclass(frozen=True)
class WineTrainingDataSplit:
    """
    Immutable container for the stratified train/test split.

    Stratified splitting ensures each cultivar class is proportionally
    represented in both partitions, which is critical for unbiased evaluation
    on small datasets like the 178-sample wine dataset.
    """

    X_train: pd.DataFrame
    X_test: pd.DataFrame
    y_train: pd.Series
    y_test: pd.Series
    feature_schema: FeatureSchema


def build_wine_training_features(
    dataset: RawWineDataset,
    test_size: float = 0.2,
    random_seed: int = 42,
) -> WineTrainingDataSplit:
    """
    Produce a stratified train/test split and a feature schema from the raw dataset.

    Args:
        dataset:     Validated RawWineDataset from the ingestion phase.
        test_size:   Fraction of samples reserved for evaluation (default 20%).
        random_seed: Seed for reproducible splits across pipeline runs.

    Returns:
        WineTrainingDataSplit containing X_train, X_test, y_train, y_test,
        and the FeatureSchema contract.

    ENTERPRISE EMPHASIS: Using a fixed random_seed (injected from environment)
    ensures that the same dataset always produces the same train/test split,
    making evaluation metrics comparable across model versions.
    """
    logger.info(
        "Building training features with stratified split",
        extra={"test_size": test_size, "random_seed": random_seed},
    )

    splitter = StratifiedShuffleSplit(
        n_splits=1, test_size=test_size, random_state=random_seed
    )

    train_indices, test_indices = next(
        splitter.split(dataset.features, dataset.targets)
    )

    X_train = dataset.features.iloc[train_indices].reset_index(drop=True)
    X_test = dataset.features.iloc[test_indices].reset_index(drop=True)
    y_train = dataset.targets.iloc[train_indices].reset_index(drop=True)
    y_test = dataset.targets.iloc[test_indices].reset_index(drop=True)

    feature_statistics = _compute_feature_statistics(X_train)

    schema = FeatureSchema(
        feature_names=dataset.feature_names,
        feature_statistics=feature_statistics,
        target_column=dataset.targets.name,
        target_class_names=dataset.target_class_names,
        train_size=len(X_train),
        test_size=len(X_test),
        stratified_split=True,
    )

    logger.info(
        "Feature split complete",
        extra={
            "train_samples": schema.train_size,
            "test_samples": schema.test_size,
            "n_features": len(schema.feature_names),
            "train_class_counts": y_train.value_counts().sort_index().to_dict(),
        },
    )

    return WineTrainingDataSplit(
        X_train=X_train,
        X_test=X_test,
        y_train=y_train,
        y_test=y_test,
        feature_schema=schema,
    )


def _compute_feature_statistics(X_train: pd.DataFrame) -> dict[str, dict[str, float]]:
    """
    Compute per-feature descriptive statistics from the training partition only.

    These statistics are stored in the feature schema so the inference API
    can warn (or reject) when an incoming request's values deviate significantly
    from the training distribution.
    """
    stats: dict[str, dict[str, float]] = {}
    desc = X_train.describe()
    for col in X_train.columns:
        stats[col] = {
            "mean": float(desc.loc["mean", col]),
            "std": float(desc.loc["std", col]),
            "min": float(desc.loc["min", col]),
            "max": float(desc.loc["max", col]),
            "p25": float(desc.loc["25%", col]),
            "p75": float(desc.loc["75%", col]),
        }
    return stats
