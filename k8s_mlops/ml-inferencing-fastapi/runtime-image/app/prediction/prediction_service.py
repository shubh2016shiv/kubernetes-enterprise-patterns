"""
Module: prediction_service
Purpose: Accept validated wine feature data, run model inference, and return
         a typed prediction result.
Inputs:  WineQualityFeatures (validated by Pydantic at the route boundary),
         LoadedModel (held in FastAPI application state since startup).
Outputs: WineQualityPrediction with predicted class, label, and model metadata.
Tradeoffs: The prediction service owns exactly one responsibility: transform
           validated input features into a prediction using the pre-loaded model.
           It does not load the model, validate input types, or handle HTTP
           concerns. Those belong to model_loader and routes respectively.
"""

from __future__ import annotations

# Standard library: pandas is used to create the single-row DataFrame that the
# sklearn Pipeline expects. The Pipeline was trained on a DataFrame with named
# columns matching the WINE_FEATURE_NAMES list from training.
import pandas as pd

# Local: all types imported explicitly to make dependencies readable.
from app.core.logging_config import get_logger
from app.model_loading.model_loader import LoadedModel
from app.prediction.schemas import WINE_CLASS_LABELS, WineQualityFeatures, WineQualityPrediction

logger = get_logger(__name__)


class PredictionService:
    """
    Purpose:
        Own the mapping from validated API input to model prediction output.
        This class knows nothing about HTTP, MLflow, or Kubernetes. It accepts
        features, runs prediction, and returns a typed result.
    Parameters:
        loaded_model: The LoadedModel held in FastAPI application state.
    Enterprise equivalent:
        In production, the prediction service is the layer where business logic
        such as pre-processing overrides, post-processing filters, output
        calibration, or feature transformation would live — separated from the
        HTTP routing layer (routes.py) and the model loading layer (model_loader.py).

    ENTERPRISE EMPHASIS: The Single Responsibility Principle applies here.
    If you later need to add request-level feature validation, output rounding,
    or business rule filtering, you add it in this class — not in the route
    handler and not inside the model code. This makes the behavior testable
    without a running FastAPI server.
    """

    def __init__(self, loaded_model: LoadedModel) -> None:
        self._loaded_model = loaded_model

    def predict(self, features: WineQualityFeatures) -> WineQualityPrediction:
        """
        Purpose:
            Convert validated feature data into a model prediction.
        Parameters:
            features: WineQualityFeatures Pydantic model — already validated by
                      FastAPI at the HTTP boundary. This method trusts the input.
        Return value:
            WineQualityPrediction with predicted class index, human-readable label,
            and the model version metadata.
        Failure behavior:
            If the sklearn Pipeline raises an exception (e.g., unexpected NaN),
            the exception propagates to the route handler, which returns HTTP 500.
            The exception is logged with the feature values for debugging.
        Enterprise equivalent:
            Production prediction services log a subset of features and the
            prediction result to a prediction store (Delta Lake, BigQuery, S3)
            for model monitoring, drift detection, and post-hoc analysis.
            This lab logs to stdout (captured by Kubernetes) for simplicity.
        """
        # Build a single-row DataFrame with the exact column names the training
        # pipeline used. Order and names must match WINE_FEATURE_NAMES from
        # load_wine_dataset.py. The sklearn Pipeline's StandardScaler and
        # classifier steps depend on named columns to produce correct predictions.
        feature_row = pd.DataFrame(
            [
                {
                    "alcohol": features.alcohol,
                    "malic_acid": features.malic_acid,
                    "ash": features.ash,
                    "alcalinity_of_ash": features.alcalinity_of_ash,
                    "magnesium": features.magnesium,
                    "total_phenols": features.total_phenols,
                    "flavanoids": features.flavanoids,
                    "nonflavanoid_phenols": features.nonflavanoid_phenols,
                    "proanthocyanins": features.proanthocyanins,
                    "color_intensity": features.color_intensity,
                    "hue": features.hue,
                    "od280_od315_of_diluted_wines": features.od280_od315_of_diluted_wines,
                    "proline": features.proline,
                }
            ]
        )

        logger.info(
            "Running prediction",
            extra={
                "model_uri": self._loaded_model.model_uri,
                "model_version": self._loaded_model.model_version,
            },
        )

        # mlflow.pyfunc wraps the sklearn Pipeline. The .predict() call passes
        # the DataFrame through the Pipeline's transform steps (StandardScaler)
        # and then the classifier's predict step.
        # The result is a numpy array of integer class labels: [0], [1], or [2].
        raw_prediction = self._loaded_model.pyfunc_model.predict(feature_row)

        # Extract the single prediction from the array and convert to a native int.
        predicted_class = int(raw_prediction[0])

        label = WINE_CLASS_LABELS.get(predicted_class, f"unknown_class_{predicted_class}")

        logger.info(
            "Prediction complete",
            extra={
                "predicted_class": predicted_class,
                "predicted_label": label,
                "model_version": self._loaded_model.model_version,
                "model_uri": self._loaded_model.model_uri,
            },
        )

        return WineQualityPrediction(
            predicted_class=predicted_class,
            predicted_label=label,
            served_model_uri=self._loaded_model.model_uri,
            model_version=self._loaded_model.model_version,
            registry_name=self._loaded_model.registry_name,
        )
