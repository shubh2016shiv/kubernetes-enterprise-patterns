"""
=============================================================================
FILE: ml-serving/05-custom-fastapi-serving/runtime-image/app/schemas.py
PURPOSE: Pydantic request/response models for the inference API.

ENTERPRISE CONTEXT:
  Pydantic schemas serve THREE purposes simultaneously in production:
    1. Input validation:    Reject malformed requests before they hit the model
    2. API documentation:  FastAPI auto-generates OpenAPI/Swagger docs from these
    3. Type enforcement:   Python runtime type checking for reliability

  In a microservices architecture, the request schema IS the contract between
  the client and the inference server. It belongs in a shared package
  (a separate pip-installable library) so callers and the server always agree.
=============================================================================
"""

from pydantic import BaseModel, Field, field_validator
from typing import Optional
import numpy as np


class WineFeatures(BaseModel):
    """
    Input schema for a single wine quality prediction request.

    Each field corresponds to one feature the GradientBoostingClassifier expects.
    The field names MUST EXACTLY match the feature_names from training
    (stored in model_metadata.json). Mismatch = wrong feature order = wrong predictions.

    ENTERPRISE TRAINING-SERVING SKEW PREVENTION:
      The model's Pipeline.predict() expects features in a specific order.
      We use model_metadata.json["input_schema"]["features"] at startup
      to verify the schema field order matches the trained model's expectation.
      This is validated in model_loader.py::ModelLoader.verify_schema().
    """
    alcohol: float = Field(
        ...,                        # "..." means required (no default)
        ge=0.0,                     # greater-than-or-equal-to 0 (non-negative alcohol)
        le=20.0,                    # upper bound (physical limit for wine)
        description="Alcohol content percentage",
        example=13.0,
    )
    malic_acid: float = Field(..., ge=0.0, le=10.0, description="Malic acid content (g/L)", example=1.71)
    ash: float = Field(..., ge=0.0, le=5.0, description="Ash content (g/L)", example=2.43)
    alcalinity_of_ash: float = Field(..., ge=0.0, le=30.0, description="Alcalinity of ash", example=15.6)
    magnesium: float = Field(..., ge=0.0, le=200.0, description="Magnesium content (mg/L)", example=127.0)
    total_phenols: float = Field(..., ge=0.0, le=5.0, description="Total phenols", example=2.80)
    flavanoids: float = Field(..., ge=0.0, le=6.0, description="Flavanoids content", example=3.06)
    nonflavanoid_phenols: float = Field(..., ge=0.0, le=1.0, description="Non-flavanoid phenols", example=0.28)
    proanthocyanins: float = Field(..., ge=0.0, le=4.0, description="Proanthocyanins content", example=2.29)
    color_intensity: float = Field(..., ge=0.0, le=15.0, description="Color intensity", example=5.64)
    hue: float = Field(..., ge=0.0, le=2.0, description="Hue of wine", example=1.04)
    od280_od315_of_diluted_wines: float = Field(
        ..., ge=0.0, le=5.0,
        description="OD280/OD315 of diluted wines",
        example=3.92
    )
    proline: float = Field(..., ge=0.0, le=2000.0, description="Proline content (mg/L)", example=1065.0)

    @field_validator("*", mode="before")
    @classmethod
    def check_not_nan(cls, v):
        """
        Reject NaN/infinity values before they reach the model.

        WHY: sklearn models return NaN predictions for NaN inputs — silently.
        Returning NaN to users causes downstream failures that are hard to trace.
        Reject early with a clear error message, not a cryptic downstream failure.
        This is the "fail fast" principle in production systems.
        """
        if isinstance(v, float) and (np.isnan(v) or np.isinf(v)):
            raise ValueError(f"Feature value cannot be NaN or infinity")
        return v

    def to_feature_array(self) -> list:
        """
        Convert to ordered list matching the training feature order.
        The ORDER must match model_metadata.json["input_schema"]["features"].
        FastAPI's .model_dump() respects field definition order.
        """
        return list(self.model_dump().values())

    model_config = {
        "json_schema_extra": {
            "example": {
                "alcohol": 13.0,
                "malic_acid": 1.71,
                "ash": 2.43,
                "alcalinity_of_ash": 15.6,
                "magnesium": 127.0,
                "total_phenols": 2.80,
                "flavanoids": 3.06,
                "nonflavanoid_phenols": 0.28,
                "proanthocyanins": 2.29,
                "color_intensity": 5.64,
                "hue": 1.04,
                "od280_od315_of_diluted_wines": 3.92,
                "proline": 1065.0
            }
        }
    }


class PredictionResponse(BaseModel):
    """
    Standardized response envelope for every prediction.

    ENTERPRISE API DESIGN PRINCIPLES:
      1. Always include model_version → enables correlation between prediction
         and the exact model artifact that produced it (auditability)
      2. Include probabilities → callers can apply their own confidence thresholds
      3. Include request_id → end-to-end tracing from client log to server log to model
      4. Consistent schema across all ML endpoints → clients need one parser
    """
    predicted_class: int = Field(..., description="Predicted wine class (0, 1, or 2)")
    class_name: str = Field(..., description="Human-readable class label")
    probabilities: dict[str, float] = Field(
        ...,
        description="Per-class prediction probability (confidence scores)"
    )
    model_version: str = Field(..., description="Version of the model that made this prediction")
    request_id: Optional[str] = Field(None, description="Unique request trace ID (set by caller or generated)")


class BatchPredictionRequest(BaseModel):
    """
    Batch inference request — send multiple samples in a single HTTP call.

    ENTERPRISE SCALING CONTEXT:
      For thousands of users, batch inference is significantly more efficient:
        - 1 API call for 100 predictions vs 100 API calls for 1 prediction each
        - Network overhead: 100x reduction
        - Model overhead: batched inference is faster than serial single-sample inference
          because modern ML frameworks (PyTorch, XGBoost) vectorize batch operations

      TRADEOFF: Batch size vs latency
        - Larger batches → better throughput but higher latency per response
        - In enterprise: expose BOTH /predict (single) and /predict/batch
          - /predict → real-time UX (latency < 100ms)
          - /predict/batch → analytics, bulk scoring (latency < 5s)

      LIMIT: Cap max_batch_size in production to prevent OOM.
      A user sending 10,000 samples in one request could OOM the pod.
    """
    samples: list[WineFeatures] = Field(
        ...,
        min_length=1,
        max_length=500,       # Hard cap: prevents OOM from oversized batches
        description="List of wine samples to classify (max 500 per request)"
    )


class BatchPredictionResponse(BaseModel):
    """Batch response — same structure as single but as a list."""
    predictions: list[PredictionResponse]
    total_samples: int
    model_version: str


class HealthResponse(BaseModel):
    """
    Response for /health — liveness check.
    Returns minimal info: is the HTTP server alive?
    This must be FAST and never touch the model or any external dependencies.
    A slow /health means K8s marks the pod as dead and restarts it — cascading failure.
    """
    status: str        # "healthy" or "degraded"
    version: str       # App version (from environment variable)


class ReadinessResponse(BaseModel):
    """
    Response for /ready — readiness check.
    Returns whether the model is loaded and the server can accept inference requests.

    CRITICAL DISTINCTION (liveness vs readiness):
      /health (liveness):  Is the Python process responding? → K8s restart on failure
      /ready (readiness):  Is the MODEL loaded? → K8s removes from LB on failure

    WHY SEPARATE?
      Model loading takes 5-60 seconds for large models.
      During loading: /health returns 200 (process is alive)
                      /ready returns 503 (model not loaded yet → no traffic sent)
      After loading:  both return 200 → traffic begins

      Without this separation: K8s would send traffic to a pod still loading
      its model → predict() called before model loaded → 500 errors for users.
    """
    status: str           # "ready" or "not_ready"
    model_loaded: bool
    model_version: Optional[str] = None
    model_name: Optional[str] = None


class ModelInfoResponse(BaseModel):
    """Model metadata endpoint — transparency into what's running."""
    name: str
    version: str
    algorithm: str
    framework: str
    trained_at: str
    metrics: dict
    input_features: list[str]
    status: str
