"""
Optuna hyperparameter search space definitions for each model family.

Each function in this module takes an optuna.Trial and returns a dict of
hyperparameters sampled from the search space. The trainer calls the
appropriate function based on the model family name selected for that trial.

Adding a new model family means adding one function here and registering its
name in training_pipeline.yaml — no other file changes required.

ENTERPRISE EMPHASIS: Centralising search space definitions in one module (rather
than inlining them in the objective function) makes it straightforward to version
the search spaces independently of the model training logic. When a model family
misbehaves in production, the search bounds can be tightened in a config PR
without touching the training code.
"""

from __future__ import annotations

from typing import Any

import optuna


ModelFamilyName = str
HyperparameterDict = dict[str, Any]


def suggest_random_forest_params(trial: optuna.Trial) -> HyperparameterDict:
    """
    Search space for sklearn RandomForestClassifier.

    The pipeline prefix 'classifier__' is required because these params are
    passed to a named step inside a sklearn Pipeline object.
    """
    return {
        "classifier__n_estimators": trial.suggest_int("rf_n_estimators", 50, 400, step=50),
        "classifier__max_depth": trial.suggest_int("rf_max_depth", 3, 20),
        "classifier__min_samples_split": trial.suggest_int("rf_min_samples_split", 2, 20),
        "classifier__min_samples_leaf": trial.suggest_int("rf_min_samples_leaf", 1, 10),
        "classifier__max_features": trial.suggest_categorical(
            "rf_max_features", ["sqrt", "log2", None]
        ),
        "classifier__class_weight": trial.suggest_categorical(
            "rf_class_weight", ["balanced", None]
        ),
    }


def suggest_gradient_boosting_params(trial: optuna.Trial) -> HyperparameterDict:
    """
    Search space for sklearn GradientBoostingClassifier.

    ENTERPRISE EMPHASIS: GradientBoosting is sensitive to learning_rate and
    n_estimators interaction. Sampling learning_rate on a log scale covers the
    typical enterprise range (0.01 to 0.3) more efficiently than uniform sampling.
    """
    return {
        "classifier__n_estimators": trial.suggest_int("gb_n_estimators", 50, 300, step=50),
        "classifier__learning_rate": trial.suggest_float(
            "gb_learning_rate", 1e-3, 0.3, log=True
        ),
        "classifier__max_depth": trial.suggest_int("gb_max_depth", 2, 8),
        "classifier__min_samples_split": trial.suggest_int("gb_min_samples_split", 2, 20),
        "classifier__subsample": trial.suggest_float("gb_subsample", 0.6, 1.0),
        "classifier__max_features": trial.suggest_categorical(
            "gb_max_features", ["sqrt", "log2", None]
        ),
    }


def suggest_logistic_regression_params(trial: optuna.Trial) -> HyperparameterDict:
    """
    Search space for sklearn LogisticRegression (multi-class, L1/L2 regularisation).

    LogisticRegression serves as the interpretable baseline model. In enterprise
    settings it is often preferred for regulated domains (credit, healthcare) where
    model explainability is a compliance requirement.

    Solver is fixed to 'saga' because it is the only sklearn solver that supports
    both l1 and l2 penalties with multi-class targets, which avoids Optuna's
    constraint that categorical distributions must have a static choice list across
    all trials (dynamic choices raise CategoricalDistribution errors).
    """
    return {
        "classifier__C": trial.suggest_float("lr_C", 1e-4, 100.0, log=True),
        "classifier__penalty": trial.suggest_categorical("lr_penalty", ["l1", "l2"]),
        "classifier__solver": "saga",
        "classifier__max_iter": trial.suggest_int("lr_max_iter", 500, 3000, step=500),
        "classifier__class_weight": trial.suggest_categorical(
            "lr_class_weight", ["balanced", None]
        ),
    }


SEARCH_SPACE_REGISTRY: dict[ModelFamilyName, Any] = {
    "random_forest": suggest_random_forest_params,
    "gradient_boosting": suggest_gradient_boosting_params,
    "logistic_regression": suggest_logistic_regression_params,
}


def get_search_space_fn(model_family: ModelFamilyName):
    """Return the hyperparameter suggestion function for a given model family."""
    if model_family not in SEARCH_SPACE_REGISTRY:
        raise ValueError(
            f"Unknown model family '{model_family}'. "
            f"Registered families: {list(SEARCH_SPACE_REGISTRY.keys())}"
        )
    return SEARCH_SPACE_REGISTRY[model_family]
