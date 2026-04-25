"""
Module: schemas
Purpose: Pydantic request and response models for the wine quality prediction
         endpoint. Defines the exact input feature contract and output label
         contract this API exposes to callers.
Inputs:  HTTP request body parsed by FastAPI.
Outputs: Validated Python objects; serialized as JSON in HTTP responses.
Tradeoffs: Pydantic v2 validates field types and ranges at the HTTP boundary.
           Invalid requests are rejected with HTTP 422 before any model code runs.
           This is the correct enterprise pattern: validate at the system boundary,
           not inside the prediction service or model code.
"""

from __future__ import annotations

# Third-party: Pydantic v2 models for request/response schema definition.
# FastAPI uses these for:
#  - Automatic JSON parsing and type coercion on the incoming request.
#  - HTTP 422 Unprocessable Entity with field-level errors on invalid input.
#  - OpenAPI schema generation (visible at /docs and /openapi.json).
from pydantic import BaseModel, Field

# The 13 features are the exact chemical measurements from the UCI Wine dataset
# that the training pipeline used. Order matters: the sklearn Pipeline expects
# features in exactly this column order. If a caller omits a field or misspells
# one, Pydantic rejects the request with a 422 before any prediction runs.
#
# Feature name reference (matching WINE_FEATURE_NAMES in load_wine_dataset.py):
#   alcohol, malic_acid, ash, alcalinity_of_ash, magnesium, total_phenols,
#   flavanoids, nonflavanoid_phenols, proanthocyanins, color_intensity, hue,
#   od280_od315_of_diluted_wines, proline


class WineQualityFeatures(BaseModel):
    """
    Purpose:
        Represent one wine sample submitted for classification. Each field is
        a continuous chemical measurement from the UCI Wine dataset.
    Parameters:
        Fields are validated by Pydantic from the JSON request body.
    Return value:
        This is a Pydantic model, not a function. FastAPI uses it as the
        request body schema for the POST /predict endpoint.
    Failure behavior:
        Missing or non-numeric fields trigger HTTP 422 with per-field error
        messages. Callers receive a machine-readable error without the request
        reaching the prediction service.
    Enterprise equivalent:
        In production, the feature schema would be versioned alongside the
        model. Schema changes (adding or removing features) require a new model
        version and a coordinated API version bump to prevent silent mismatch
        failures. In this lab, we use the exact feature list from training.

    ENTERPRISE EMPHASIS: The prediction API schema is a data contract between
    upstream services (feature pipelines, user-facing apps) and the model. Any
    change to feature names or types is a breaking change. Schema versioning
    (e.g., /v1/predict, /v2/predict) gives upstream teams time to migrate
    without a simultaneous forced cutover.
    """

    alcohol: float = Field(..., description="Alcohol content (% by volume).")
    malic_acid: float = Field(..., description="Malic acid concentration (g/L).")
    ash: float = Field(..., description="Ash mineral content (g/L).")
    alcalinity_of_ash: float = Field(..., description="Alkalinity of ash (mEq/L).")
    magnesium: float = Field(..., description="Magnesium content (mg/L).")
    total_phenols: float = Field(..., description="Total phenol concentration (g/L).")
    flavanoids: float = Field(..., description="Flavanoid concentration (g/L).")
    nonflavanoid_phenols: float = Field(
        ..., description="Non-flavanoid phenol concentration (g/L)."
    )
    proanthocyanins: float = Field(..., description="Proanthocyanin concentration (g/L).")
    color_intensity: float = Field(..., description="Color intensity (absorbance units).")
    hue: float = Field(..., description="Color hue ratio (dimensionless).")
    od280_od315_of_diluted_wines: float = Field(
        ...,
        description=(
            "OD280/OD315 absorbance ratio of diluted wines. "
            "A measure of protein content and wine clarity."
        ),
    )
    proline: float = Field(..., description="Proline amino acid content (mg/L).")


class WineQualityPrediction(BaseModel):
    """
    Purpose:
        Represent the prediction result returned to the caller. Carries the
        predicted class label, the model version that produced it, and metadata
        useful for debugging and audit.
    Return value:
        Serialized as the JSON response body by FastAPI.
    Enterprise equivalent:
        Production prediction responses typically include the model version,
        a request trace ID for distributed tracing, and a confidence score.
        Including the model version in every response makes it possible to
        detect inconsistency when some pods serve a different version during a
        rolling update.
    """

    predicted_class: int = Field(
        description=(
            "Predicted wine cultivar class index (0, 1, or 2). "
            "Corresponds to the three cultivar classes in the UCI Wine dataset."
        ),
    )

    predicted_label: str = Field(
        description=(
            "Human-readable class label: class_0, class_1, or class_2. "
            "Matches the target_names from sklearn.datasets.load_wine()."
        ),
    )

    served_model_uri: str = Field(
        description=(
            "Immutable MLflow model URI this pod loaded at startup. "
            "Example: models:/wine-quality-classifier-prod/1. "
            "Include this in bug reports to identify which model version produced the result."
        ),
    )

    model_version: str = Field(
        description="Model version number, e.g. 1. Extracted from served_model_uri.",
    )

    registry_name: str = Field(
        description="MLflow registered model name. e.g. wine-quality-classifier-prod.",
    )


# Canonical class label mapping — must match sklearn.datasets.load_wine().target_names.
# Index 0 → class_0, Index 1 → class_1, Index 2 → class_2.
WINE_CLASS_LABELS: dict[int, str] = {
    0: "class_0",
    1: "class_1",
    2: "class_2",
}
