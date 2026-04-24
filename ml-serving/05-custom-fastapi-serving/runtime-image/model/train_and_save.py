"""
=============================================================================
FILE: ml-serving/05-custom-fastapi-serving/runtime-image/model/train_and_save.py
PURPOSE: Train a realistic ML model and persist the artifact as a .pkl file.

ENTERPRISE CONTEXT:
  In a real ML pipeline, this script runs in a TRAINING environment
  (not the inference server). Training might happen on:
    - A GPU workstation / EC2 P-instance
    - A Kubernetes Job (batch, not a Deployment)
    - A managed service: AWS SageMaker, Azure ML, GCP Vertex AI

  The OUTPUT of training (the .pkl artifact) is then uploaded to:
    - AWS S3: s3://ml-models-bucket/wine-quality/v1.2.0/model.pkl
    - Azure Blob: https://storage.blob.core.windows.net/models/wine-quality/v1.2.0/model.pkl
    - GCS: gs://company-ml-models/wine-quality/v1.2.0/model.pkl

  The INFERENCE SERVER (FastAPI in Kubernetes) downloads this artifact at
  startup time. It does NOT re-train. It only SERVES predictions.

WHAT THIS SCRIPT DOES:
  1. Loads the Wine Quality dataset (UCI ML Repository — real, tabular data)
  2. Trains a GradientBoostingClassifier (a real production-grade algorithm)
  3. Evaluates on a holdout test set (accuracy, classification report)
  4. Saves a metadata JSON alongside the pkl (model versioning)
  5. Saves the artifact to ./artifacts/model.pkl

RUN THIS:
  cd ml-serving/05-custom-fastapi-serving/runtime-image/model
  pip install scikit-learn numpy pandas joblib
  python train_and_save.py
=============================================================================
"""

import json
import os
import sys
import hashlib
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.datasets import load_wine          # Real UCI dataset — 178 samples, 13 features
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline           # Scaler + model in ONE pkl (enterprise pattern)
from sklearn.metrics import classification_report, accuracy_score
import joblib                                  # Preferred over pickle for sklearn models
                                               # joblib uses memory-mapped files for large arrays
                                               # pickle is pure Python — slower for numpy arrays

# ─── CONFIGURATION ────────────────────────────────────────────────────────────
# All tuneable values live at the top — not hardcoded inside functions
# In enterprise ML: these would come from MLflow, Weights & Biases, or a
# Hydra/OmegaConf configuration system

MODEL_VERSION = "1.0.0"
MODEL_NAME = "wine-quality-classifier"

# Artifact output directory — this gets mounted as a PVC in Kubernetes
ARTIFACT_DIR = Path(__file__).parent / "artifacts"

# Training hyperparameters
# In enterprise: these are tracked in MLflow Experiments alongside metrics
HYPERPARAMS = {
    "n_estimators": 200,          # Number of boosting stages (trees)
    "learning_rate": 0.05,        # Shrinkage: smaller = better generalization, slower
    "max_depth": 4,               # Tree depth: controls overfitting
    "subsample": 0.8,             # Fraction of samples per tree (stochastic GB)
    "random_state": 42,           # Seed for reproducibility — ALWAYS set in enterprise
    "min_samples_split": 10,      # Minimum samples to split a node
}


def load_and_prepare_data():
    """
    Load the Wine Quality dataset and prepare train/test splits.

    ENTERPRISE NOTE: In production, data would come from:
      - A Feature Store (Feast, Tecton, AWS SageMaker Feature Store)
      - A data warehouse query (Snowflake, BigQuery, Redshift)
      - An S3/GCS data lake with versioned datasets

    The Feature Store ensures:
      - Training and inference use IDENTICAL feature transformations
      - No training-serving skew (the #1 cause of silent model degradation)
      - Point-in-time correct features (no data leakage)
    """
    print("[1/5] Loading Wine Quality dataset...")

    # load_wine() returns the classic UCI Wine dataset:
    #   - 178 samples, 13 features (alcohol, malic acid, ash, etc.)
    #   - 3 classes (wine cultivar: 0, 1, 2)
    #   - Perfectly clean, no missing values (great for demos)
    dataset = load_wine()

    # Convert to DataFrame for inspection and logging
    df = pd.DataFrame(dataset.data, columns=dataset.feature_names)
    df["target"] = dataset.target

    print(f"  Dataset shape: {df.shape}")
    print(f"  Features: {list(dataset.feature_names)}")
    print(f"  Classes: {dataset.target_names.tolist()}")
    print(f"  Class distribution: {df['target'].value_counts().to_dict()}")

    X = dataset.data
    y = dataset.target

    # train_test_split with stratify=y ensures class proportions are preserved
    # CRITICAL in enterprise: without stratify, small datasets can produce
    # test sets missing entire classes → misleadingly high accuracy
    X_train, X_test, y_train, y_test = train_test_split(
        X, y,
        test_size=0.20,           # 20% holdout — standard for small datasets
        random_state=HYPERPARAMS["random_state"],
        stratify=y                # Preserve class proportions in both splits
    )

    print(f"  Train samples: {len(X_train)}, Test samples: {len(X_test)}")

    return X_train, X_test, y_train, y_test, dataset.feature_names, dataset.target_names


def build_pipeline(hyperparams: dict) -> Pipeline:
    """
    Build a sklearn Pipeline wrapping preprocessing + model.

    WHY A PIPELINE (critical for serving):
      Packing the scaler INSIDE the pipeline means the pkl artifact
      contains BOTH the fitted scaler AND the trained model.

      When the inference server loads model.pkl and calls .predict(),
      it automatically scales the input before prediction — no manual
      preprocessing required. This eliminates training-serving skew
      from inconsistent preprocessing.

      Without Pipeline: you'd need TWO pkl files (scaler.pkl + model.pkl)
      and must apply scaler first in the serving code. Error-prone.

      With Pipeline: model.predict(raw_input) handles everything.
      One artifact, one call, no skew.
    """
    return Pipeline([
        # StandardScaler: subtracts mean, divides by std deviation
        # GradientBoosting is NOT sensitive to scale (trees don't use distances)
        # but StandardScaler is good practice for tabular data pipelines
        # because it makes the pipeline robust to algorithm switches
        ("scaler", StandardScaler()),
        ("classifier", GradientBoostingClassifier(**hyperparams))
    ])


def evaluate_model(pipeline, X_train, X_test, y_train, y_test, target_names):
    """
    Evaluate model performance with both cross-validation and holdout metrics.
    Returns a metrics dict suitable for storage in model metadata.
    """
    print("[3/5] Evaluating model...")

    # Cross-validation on training data (more robust than single split)
    # cv=5 → 5-fold: each fold is used once as validation
    cv_scores = cross_val_score(pipeline, X_train, y_train, cv=5, scoring="accuracy")
    print(f"  Cross-val accuracy: {cv_scores.mean():.4f} ± {cv_scores.std():.4f}")

    # Final evaluation on holdout test set (data the model NEVER saw)
    y_pred = pipeline.predict(X_test)
    test_accuracy = accuracy_score(y_test, y_pred)

    print(f"  Test accuracy: {test_accuracy:.4f}")
    print("\n  Classification Report:")
    print(classification_report(y_test, y_pred, target_names=target_names))

    return {
        "cv_accuracy_mean": round(float(cv_scores.mean()), 4),
        "cv_accuracy_std": round(float(cv_scores.std()), 4),
        "test_accuracy": round(float(test_accuracy), 4),
    }


def compute_file_sha256(filepath: Path) -> str:
    """
    Compute SHA-256 checksum of the saved model file.

    ENTERPRISE SECURITY PRACTICE:
      Every artifact that gets deployed must have a verified checksum.
      The inference server validates this checksum at startup:
        1. Download model.pkl from S3
        2. Download model_metadata.json (contains expected checksum)
        3. Compute SHA-256 of downloaded file
        4. Compare to metadata.sha256
        5. If mismatch → ABORT (supply chain integrity check)

      This prevents:
        - Corrupted downloads being loaded as valid models
        - Man-in-the-middle model substitution attacks
        - Silent model drift from unauthorized artifact replacement
    """
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        # Read in 64KB chunks (handles large model files efficiently)
        for chunk in iter(lambda: f.read(65536), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def save_artifacts(pipeline, feature_names, target_names, metrics, hyperparams):
    """
    Save the model artifact and its metadata JSON.

    METADATA SCHEMA (what to track in enterprise):
      Every model artifact in production has associated metadata that answers:
        - What code trained it? (git_sha)
        - What data trained it? (dataset_version, data_hash)
        - What are its performance guarantees? (metrics)
        - Is it safe to load? (sha256 checksum)
        - Is it approved for production? (status)
        - What does it expect as input? (input_schema)
    """
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    # ── Save Model pkl ──────────────────────────────────────────────────────
    model_path = ARTIFACT_DIR / "model.pkl"

    # joblib.dump is preferred over pickle for sklearn:
    #   - Efficiently serializes large numpy arrays (memory-mapped)
    #   - compress=3 reduces file size significantly for large models
    joblib.dump(pipeline, model_path, compress=3)
    print(f"\n  Model saved: {model_path}")
    print(f"  File size: {model_path.stat().st_size / 1024:.1f} KB")

    # ── Compute Checksum ────────────────────────────────────────────────────
    sha256_hash = compute_file_sha256(model_path)
    print(f"  SHA-256: {sha256_hash[:16]}...")

    # ── Save Metadata JSON ──────────────────────────────────────────────────
    metadata = {
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "framework": "scikit-learn",
        "algorithm": "GradientBoostingClassifier",
        "artifact_file": "model.pkl",
        "sha256": sha256_hash,              # Integrity checksum

        # Training provenance
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "dataset": "UCI Wine Quality (sklearn.datasets.load_wine)",
        "hyperparameters": hyperparams,

        # Performance (contract with downstream consumers)
        "metrics": metrics,

        # Schema (what the inference server must validate at predict time)
        # In enterprise: this is defined by a Feature Store schema or OpenAPI spec
        "input_schema": {
            "type": "object",
            "features": list(feature_names),
            "feature_count": len(feature_names),
            "dtype": "float64"
        },
        "output_schema": {
            "type": "object",
            "fields": {
                "predicted_class": "int",
                "class_name": "str",
                "probabilities": "dict[str, float]",
                "model_version": "str"
            }
        },
        "target_names": list(target_names),

        # Operational metadata
        "status": "ready",   # In enterprise MLflow: Staging → Production workflow
        "min_replicas": 2,   # Minimum K8s replicas recommended (HA)
        "memory_estimate_mb": 50,  # Approximate memory to inform K8s resource requests
    }

    metadata_path = ARTIFACT_DIR / "model_metadata.json"
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)
    print(f"  Metadata saved: {metadata_path}")

    return model_path, metadata_path


def main():
    print("=" * 60)
    print(f"  ML Model Training Pipeline")
    print(f"  Model: {MODEL_NAME} v{MODEL_VERSION}")
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    # Step 1: Data
    X_train, X_test, y_train, y_test, feature_names, target_names = load_and_prepare_data()

    # Step 2: Build
    print("\n[2/5] Building Pipeline (StandardScaler + GradientBoostingClassifier)...")
    pipeline = build_pipeline(HYPERPARAMS)

    # Step 3: Train
    print("[2/5] Training...")
    pipeline.fit(X_train, y_train)
    print("  Training complete.")

    # Step 4: Evaluate
    metrics = evaluate_model(pipeline, X_train, X_test, y_train, y_test, target_names)

    # Step 5: Save
    print("[4/5] Saving artifacts...")
    save_artifacts(pipeline, feature_names, target_names, metrics, HYPERPARAMS)

    print("\n[5/5] Done!")
    print("=" * 60)
    print(f"  Artifacts in: {ARTIFACT_DIR.resolve()}")
    print(f"  Next: Build Docker image and load into kind cluster")
    print(f"  → cd .. && bash build-and-load.sh")
    print("=" * 60)


if __name__ == "__main__":
    main()
