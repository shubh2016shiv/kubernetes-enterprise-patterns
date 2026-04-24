#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/02-local-model-registry/load-model-into-pvc.sh
#
# PURPOSE:
#   Copy a pre-trained local sklearn model into the Kubernetes PVC.
#
# INPUT:
#   A joblib-serialized sklearn artifact.
#
#   KServe convention expects the file name to be:
#     model.joblib
#
#   If your training code produced `model.pkl` using joblib.dump(), that is
#   still a joblib artifact. This script copies it into the PVC as model.joblib.
#
# USAGE:
#   bash ml-serving/02-local-model-registry/load-model-into-pvc.sh \
#     path/to/model.pkl
#
# AFTER THIS:
#   Deploy:
#     kubectl apply -f ml-serving/03-wine-quality-inferenceservice/01-wine-quality-sklearn-isvc.yaml
# =============================================================================

set -euo pipefail

MODEL_ARTIFACT="${1:-}"

if [[ -z "${MODEL_ARTIFACT}" ]]; then
  echo "ERROR: Pass the path to your trained sklearn model artifact."
  echo "Example:"
  echo "  bash ml-serving/02-local-model-registry/load-model-into-pvc.sh ./model.pkl"
  exit 1
fi

if [[ ! -f "${MODEL_ARTIFACT}" ]]; then
  echo "ERROR: File not found: ${MODEL_ARTIFACT}"
  exit 1
fi

echo "==> Creating namespace and PVC"
kubectl apply -f ml-serving/02-local-model-registry/01-namespace.yaml
kubectl apply -f ml-serving/02-local-model-registry/02-model-store-pvc.yaml

echo "==> Starting temporary loader pod"
kubectl apply -f ml-serving/02-local-model-registry/03-model-store-loader-pod.yaml
kubectl wait --for=condition=Ready pod/wine-model-store-loader \
  --namespace ml-serving \
  --timeout=120s

echo "==> Creating versioned folder inside PVC"
kubectl exec -n ml-serving wine-model-store-loader -- \
  mkdir -p /mnt/models/wine-quality/v1

echo "==> Copying artifact into PVC as model.joblib"
kubectl cp "${MODEL_ARTIFACT}" \
  ml-serving/wine-model-store-loader:/mnt/models/wine-quality/v1/model.joblib \
  -c loader

echo "==> Verifying PVC contents"
kubectl exec -n ml-serving wine-model-store-loader -- \
  ls -lh /mnt/models/wine-quality/v1

echo "==> Removing temporary loader pod"
kubectl delete pod wine-model-store-loader -n ml-serving --wait=true

echo "==> Model store ready: pvc://wine-model-store/wine-quality/v1/"

