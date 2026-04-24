"""
Model training phase: run Optuna hyperparameter search across all configured
model families and return the best-fitted sklearn Pipeline.

Design:
  - One Optuna Study runs across all model families in a single search.
    Each trial picks a model family at random and samples from its search space.
  - Each trial is evaluated using stratified k-fold cross-validation on the
    training split. The test split is never touched during search.
  - The best trial's hyperparameters are used to refit the winning pipeline
    on the full training split before artifact serialisation.

ENTERPRISE EMPHASIS: Using cross-validation scores (not hold-out test scores)
as the Optuna objective prevents the test set from becoming part of the
hyperparameter selection process. The test set is reserved exclusively for the
evaluation phase so that reported metrics are unbiased estimates of
generalisation performance.
"""

from __future__ import annotations

import warnings
from dataclasses import dataclass
from typing import Any

import numpy as np
import optuna
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from wine_quality_training.feature_engineering.build_wine_features import WineTrainingDataSplit
from wine_quality_training.training.hyperparameter_search_config import get_search_space_fn
from wine_quality_training.training.training_pipeline_config import TrainingPipelineConfig
from wine_quality_training.shared.structured_logger import get_pipeline_logger

logger = get_pipeline_logger(__name__, phase="model_training")

optuna.logging.set_verbosity(optuna.logging.WARNING)


MODEL_FAMILY_CONSTRUCTORS: dict[str, Any] = {
    "random_forest": RandomForestClassifier,
    "gradient_boosting": GradientBoostingClassifier,
    "logistic_regression": LogisticRegression,
}


@dataclass
class TrainingResult:
    """
    Output of the training phase.

    Carries the fitted pipeline, the best trial metadata, and the model family
    name. All three are required by the evaluation and model_registry phases.
    """

    fitted_pipeline: Pipeline
    best_model_family: str
    best_hyperparameters: dict[str, Any]
    best_cv_score: float
    cv_metric: str
    n_trials_completed: int
    n_training_samples: int


def run_hyperparameter_search_and_train(
    data_split: WineTrainingDataSplit,
    config: TrainingPipelineConfig,
) -> TrainingResult:
    """
    Run Optuna cross-validation search across all model families, then refit
    the winning pipeline on the full training split.

    Args:
        data_split: Stratified train/test split from the feature engineering phase.
        config:     Resolved TrainingPipelineConfig.

    Returns:
        TrainingResult with the fitted pipeline and best trial metadata.
    """
    logger.info(
        "Starting hyperparameter search",
        extra={
            "model_families": config.model_family_names,
            "n_trials": config.optuna.n_trials,
            "cv_folds": config.cv_folds,
            "cv_metric": config.optuna.metric,
        },
    )

    X_train = data_split.X_train
    y_train = data_split.y_train

    cv_splitter = StratifiedKFold(
        n_splits=config.cv_folds, shuffle=True, random_state=config.random_seed
    )

    def optuna_objective(trial: optuna.Trial) -> float:
        model_family = trial.suggest_categorical(
            "model_family", config.model_family_names
        )
        search_fn = get_search_space_fn(model_family)
        hyperparams = search_fn(trial)

        pipeline = _build_pipeline(model_family, config.random_seed)
        pipeline.set_params(**hyperparams)

        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            cv_scores = cross_val_score(
                pipeline,
                X_train,
                y_train,
                cv=cv_splitter,
                scoring=config.optuna.metric,
                n_jobs=-1,
            )

        return float(np.mean(cv_scores))

    study = optuna.create_study(
        direction=config.optuna.direction,
        sampler=optuna.samplers.TPESampler(seed=config.random_seed),
    )
    study.optimize(
        optuna_objective,
        n_trials=config.optuna.n_trials,
        timeout=config.optuna.timeout_seconds,
        show_progress_bar=False,
    )

    best_trial = study.best_trial
    best_family = best_trial.params["model_family"]
    best_params = {
        k: v for k, v in best_trial.params.items() if k != "model_family"
    }

    logger.info(
        "Hyperparameter search complete — refitting best pipeline on full training split",
        extra={
            "best_model_family": best_family,
            "best_cv_score": round(best_trial.value, 4),
            "n_trials_completed": len(study.trials),
        },
    )

    best_pipeline = _build_pipeline(best_family, config.random_seed)
    pipeline_params = _trial_params_to_pipeline_params(best_params, best_family)
    best_pipeline.set_params(**pipeline_params)

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        best_pipeline.fit(X_train, y_train)

    logger.info(
        "Pipeline refit complete",
        extra={
            "best_model_family": best_family,
            "n_training_samples": len(X_train),
        },
    )

    return TrainingResult(
        fitted_pipeline=best_pipeline,
        best_model_family=best_family,
        best_hyperparameters=pipeline_params,
        best_cv_score=best_trial.value,
        cv_metric=config.optuna.metric,
        n_trials_completed=len(study.trials),
        n_training_samples=len(X_train),
    )


def _build_pipeline(model_family: str, random_seed: int) -> Pipeline:
    """
    Construct a StandardScaler + classifier sklearn Pipeline.

    StandardScaler is always included so that gradient-based and distance-based
    models (LogisticRegression) perform fairly. Tree-based models are invariant
    to scaling but including it causes no harm and keeps the pipeline uniform.

    ENTERPRISE EMPHASIS: Bundling the scaler inside the Pipeline ensures the
    scaler is fitted only on training data and is serialised as a single
    artifact. A scaler fitted separately and stored apart from the model is
    an easy path to training-serving skew.
    """
    if model_family not in MODEL_FAMILY_CONSTRUCTORS:
        raise ValueError(f"Unknown model family '{model_family}'")

    constructor = MODEL_FAMILY_CONSTRUCTORS[model_family]
    classifier_kwargs: dict[str, Any] = {}

    if model_family in ("random_forest", "gradient_boosting"):
        classifier_kwargs["random_state"] = random_seed
    elif model_family == "logistic_regression":
        classifier_kwargs["random_state"] = random_seed
        classifier_kwargs["solver"] = "saga"

    return Pipeline(
        steps=[
            ("scaler", StandardScaler()),
            ("classifier", constructor(**classifier_kwargs)),
        ]
    )


def _trial_params_to_pipeline_params(
    trial_params: dict[str, Any], model_family: str
) -> dict[str, Any]:
    """
    Convert raw Optuna trial param names back to sklearn Pipeline param names.

    Optuna stores params with family-prefixed names (e.g. 'rf_n_estimators').
    sklearn Pipeline set_params expects step-prefixed names ('classifier__n_estimators').

    Fixed constructor kwargs (e.g. solver='saga' for logistic_regression) are
    not in trial_params because they were never sampled — they are already baked
    into the pipeline built by _build_pipeline().
    """
    prefix_map = {
        "random_forest": "rf_",
        "gradient_boosting": "gb_",
        "logistic_regression": "lr_",
    }
    prefix = prefix_map[model_family]
    pipeline_params: dict[str, Any] = {}
    for k, v in trial_params.items():
        if not k.startswith(prefix):
            continue
        clean_key = k[len(prefix):]
        pipeline_params[f"classifier__{clean_key}"] = v
    return pipeline_params
