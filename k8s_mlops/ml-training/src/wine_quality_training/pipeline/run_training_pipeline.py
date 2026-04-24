"""
Training pipeline orchestrator: execute all ML lifecycle phases in sequence.

This is the entrypoint for the Kubernetes Training Job. It calls each phase
in the correct order, passes typed outputs between phases, and halts with a
non-zero exit code if any phase fails — which causes the Kubernetes Job to
record a failure and (optionally) retry via backoffLimit.

Kubernetes Job execution flow:
  1. ConfigMap mounts training_pipeline.yaml at $PIPELINE_CONFIG_PATH
  2. Job spec injects ARTIFACT_STORE_ROOT env var (points to PVC mount path)
  3. Container runs: python -m wine_quality_training.pipeline.run_training_pipeline
  4. Pipeline executes all phases and writes artifacts to the PVC
  5. Job exits 0 on success, non-zero on any phase failure
  6. Kubernetes marks Job as Succeeded or Failed accordingly

ENTERPRISE EMPHASIS: The orchestrator is intentionally thin — it only wires
phases together. Each phase module is independently testable and importable.
This structure allows individual phases to be promoted to separate Kubernetes
Jobs in the future (e.g., data validation as a pre-training gate Job that
blocks training from starting if it fails).
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

from wine_quality_training.data_ingestion.load_wine_dataset import load_wine_dataset
from wine_quality_training.data_validation.validate_training_schema import (
    DataValidationError,
    validate_wine_training_schema,
)
from wine_quality_training.evaluation.evaluate_wine_quality_model import (
    evaluate_wine_quality_model,
)
from wine_quality_training.feature_engineering.build_wine_features import (
    build_wine_training_features,
)
from wine_quality_training.model_registry.register_model_artifact import (
    register_model_artifact,
)
from wine_quality_training.training.training_pipeline_config import (
    load_training_pipeline_config,
)
from wine_quality_training.training.wine_quality_model_trainer import (
    run_hyperparameter_search_and_train,
)
from wine_quality_training.shared.env_config import load_training_env_config
from wine_quality_training.shared.structured_logger import (
    configure_root_logging,
    get_pipeline_logger,
)

logger = get_pipeline_logger(__name__, phase="pipeline_orchestrator")


def main() -> None:
    """
    Execute the full wine quality training pipeline.

    Exit codes:
      0 — all phases succeeded and the artifact was registered
      1 — configuration or environment error (bad env vars, missing config file)
      2 — data validation failure (dataset does not meet schema contract)
      3 — evaluation failure (model did not meet promotion threshold)
      4 — unexpected runtime error in any phase
    """
    pipeline_start = time.monotonic()
    configure_root_logging()

    logger.info("=" * 60)
    logger.info("Wine Quality Training Pipeline — START")
    logger.info("=" * 60)

    try:
        env_config = load_training_env_config()
    except RuntimeError as exc:
        logger.error(f"Environment configuration error: {exc}")
        sys.exit(1)

    configure_root_logging(level=env_config.log_level)

    try:
        pipeline_config = load_training_pipeline_config(env_config.pipeline_config_path)
    except (FileNotFoundError, KeyError) as exc:
        logger.error(f"Pipeline config load error: {exc}")
        sys.exit(1)

    logger.info(
        "Configuration loaded",
        extra={
            "experiment_name": pipeline_config.experiment_name,
            "model_families": pipeline_config.model_family_names,
            "optuna_n_trials": pipeline_config.optuna.n_trials,
            "artifact_store_root": str(pipeline_config.artifact_store_root),
        },
    )

    artifact_store_root = (
        env_config.artifact_store_root
        if env_config.artifact_store_root != Path(".")
        else pipeline_config.artifact_store_root
    )

    # -------------------------------------------------------------------------
    # Phase 1: Data Ingestion
    # -------------------------------------------------------------------------
    logger.info("--- Phase 1: Data Ingestion ---")
    t0 = time.monotonic()
    raw_dataset = load_wine_dataset()
    logger.info(f"Phase 1 complete ({time.monotonic() - t0:.2f}s)")

    # -------------------------------------------------------------------------
    # Phase 2: Data Validation
    # -------------------------------------------------------------------------
    logger.info("--- Phase 2: Data Validation ---")
    t0 = time.monotonic()
    try:
        validation_report = validate_wine_training_schema(raw_dataset)
    except DataValidationError as exc:
        logger.error(f"Data validation FAILED: {exc}")
        sys.exit(2)
    logger.info(f"Phase 2 complete ({time.monotonic() - t0:.2f}s)")

    # -------------------------------------------------------------------------
    # Phase 3: Feature Engineering
    # -------------------------------------------------------------------------
    logger.info("--- Phase 3: Feature Engineering ---")
    t0 = time.monotonic()
    data_split = build_wine_training_features(
        dataset=raw_dataset,
        test_size=pipeline_config.test_size,
        random_seed=pipeline_config.random_seed,
    )
    logger.info(f"Phase 3 complete ({time.monotonic() - t0:.2f}s)")

    # -------------------------------------------------------------------------
    # Phase 4: Model Training (Optuna hyperparameter search + refit)
    # -------------------------------------------------------------------------
    logger.info("--- Phase 4: Model Training ---")
    t0 = time.monotonic()
    training_result = run_hyperparameter_search_and_train(
        data_split=data_split,
        config=pipeline_config,
    )
    logger.info(f"Phase 4 complete ({time.monotonic() - t0:.2f}s)")

    # -------------------------------------------------------------------------
    # Phase 5: Model Evaluation
    # -------------------------------------------------------------------------
    logger.info("--- Phase 5: Model Evaluation ---")
    t0 = time.monotonic()
    evaluation_result = evaluate_wine_quality_model(
        training_result=training_result,
        data_split=data_split,
        promotion_threshold=0.85,
    )
    logger.info(f"Phase 5 complete ({time.monotonic() - t0:.2f}s)")

    if not evaluation_result.evaluation_passed_threshold:
        logger.error(
            "Model did not meet promotion threshold — artifact will still be "
            "registered with evaluation_passed=false for audit purposes, "
            "but this Job exits with code 3 to signal the pipeline gate failure."
        )

    # -------------------------------------------------------------------------
    # Phase 6: Artifact Registration
    # -------------------------------------------------------------------------
    logger.info("--- Phase 6: Artifact Registration ---")
    t0 = time.monotonic()
    registered = register_model_artifact(
        training_result=training_result,
        evaluation_result=evaluation_result,
        data_split=data_split,
        artifact_store_root=artifact_store_root,
        dataset_content_hash=raw_dataset.dataset_content_hash,
        experiment_name=pipeline_config.experiment_name,
    )
    logger.info(f"Phase 6 complete ({time.monotonic() - t0:.2f}s)")

    total_duration = time.monotonic() - pipeline_start

    logger.info("=" * 60)
    logger.info(
        "Wine Quality Training Pipeline — COMPLETE",
        extra={
            "version": registered.version,
            "artifact_dir": str(registered.artifact_directory),
            "balanced_accuracy": evaluation_result.balanced_accuracy,
            "evaluation_passed": registered.evaluation_passed,
            "total_duration_seconds": round(total_duration, 1),
        },
    )
    logger.info("=" * 60)

    if not registered.evaluation_passed:
        sys.exit(3)


if __name__ == "__main__":
    main()
