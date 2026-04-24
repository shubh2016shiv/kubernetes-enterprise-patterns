"""
Data ingestion phase: load the UCI Wine dataset from scikit-learn.

In this project the dataset is bundled with scikit-learn. In a real enterprise
pipeline this phase would pull from a feature store, a data lake partition, or
a versioned dataset registry (e.g. Delta Lake, Feast, Tecton).

ENTERPRISE EMPHASIS: Even when the data source is trivial, the ingestion phase
must be kept separate because it is the first stage that could fail due to an
upstream data contract change, access permission issue, or schema drift. Keeping
it isolated makes the failure surface narrow and the root cause obvious in logs.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

import numpy as np
import pandas as pd
from sklearn.datasets import load_wine

from wine_quality_training.shared.structured_logger import get_pipeline_logger

logger = get_pipeline_logger(__name__, phase="data_ingestion")

WINE_FEATURE_NAMES: list[str] = [
    "alcohol",
    "malic_acid",
    "ash",
    "alcalinity_of_ash",
    "magnesium",
    "total_phenols",
    "flavanoids",
    "nonflavanoid_phenols",
    "proanthocyanins",
    "color_intensity",
    "hue",
    "od280_od315_of_diluted_wines",
    "proline",
]

TARGET_COLUMN: str = "wine_cultivar_class"


@dataclass(frozen=True)
class RawWineDataset:
    """
    Immutable container for the raw ingested dataset.

    Carries the feature matrix, target vector, feature names, and a
    deterministic content hash so downstream phases can detect data drift
    across pipeline runs.

    ENTERPRISE EMPHASIS: In production, the dataset_content_hash would be
    persisted alongside the model artifact to guarantee that the trained model
    can always be traced back to the exact data snapshot used at training time.
    """

    features: pd.DataFrame
    targets: pd.Series
    feature_names: list[str]
    target_class_names: list[str]
    dataset_content_hash: str
    n_samples: int
    n_features: int


def load_wine_dataset() -> RawWineDataset:
    """
    Load the UCI Wine dataset and return it as a typed, immutable container.

    The wine dataset has 178 samples across 3 cultivar classes and 13
    continuous chemical measurement features. It is used here as a
    multi-class classification target.

    Returns:
        RawWineDataset with feature DataFrame, target Series, and metadata.
    """
    logger.info("Loading UCI Wine dataset from sklearn.datasets")

    sklearn_bunch = load_wine(as_frame=True)

    features: pd.DataFrame = sklearn_bunch.frame[sklearn_bunch.feature_names].copy()
    features.columns = WINE_FEATURE_NAMES

    targets: pd.Series = sklearn_bunch.target.rename(TARGET_COLUMN)
    target_class_names: list[str] = list(sklearn_bunch.target_names)

    dataset_hash = _compute_dataset_hash(features, targets)

    dataset = RawWineDataset(
        features=features,
        targets=targets,
        feature_names=WINE_FEATURE_NAMES,
        target_class_names=target_class_names,
        dataset_content_hash=dataset_hash,
        n_samples=len(features),
        n_features=features.shape[1],
    )

    logger.info(
        "Dataset loaded successfully",
        extra={
            "n_samples": dataset.n_samples,
            "n_features": dataset.n_features,
            "target_classes": dataset.target_class_names,
            "dataset_hash": dataset.dataset_content_hash,
        },
    )

    return dataset


def _compute_dataset_hash(features: pd.DataFrame, targets: pd.Series) -> str:
    """
    Produce a SHA-256 hash of the feature matrix and target vector.

    The hash is computed over a deterministic byte representation so that
    identical data always produces the same hash regardless of load order.

    ENTERPRISE EMPHASIS: A stable dataset hash enables the model registry to
    detect when a new training run uses identical data (deduplication) or
    different data (lineage traceability for audit and compliance).
    """
    combined = np.concatenate(
        [features.values.astype(np.float64), targets.values.reshape(-1, 1).astype(np.float64)],
        axis=1,
    )
    return hashlib.sha256(combined.tobytes()).hexdigest()
