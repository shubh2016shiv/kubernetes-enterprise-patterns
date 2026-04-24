#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/04-enterprise-operations/rollout-and-debug.sh
#
# PURPOSE:
#   Daily operational commands for a KServe-deployed model.
#
# HOW TO READ THIS FILE:
#   This is not meant to be blindly executed once.
#   Treat each command block as an operator's checklist.
# =============================================================================

set -euo pipefail

NS="ml-serving"
NAME="wine-quality"

echo "==> 1. Check the business object first: InferenceService"
kubectl get inferenceservice "${NAME}" -n "${NS}" -o wide

echo
echo "==> 2. If not Ready, inspect conditions"
kubectl describe inferenceservice "${NAME}" -n "${NS}"

echo
echo "==> 3. Inspect the generated pods"
kubectl get pods -n "${NS}" -l serving.kserve.io/inferenceservice="${NAME}" -o wide

echo
echo "==> 4. Read logs from the predictor pod"
POD="$(kubectl get pods -n "${NS}" -l serving.kserve.io/inferenceservice="${NAME}" -o jsonpath='{.items[0].metadata.name}')"
kubectl logs "${POD}" -n "${NS}" --all-containers=true --tail=100

echo
echo "==> 5. Inspect autoscaling"
kubectl get hpa -n "${NS}" || true
kubectl describe hpa -n "${NS}" || true

echo
echo "==> 6. Explain storage"
kubectl get pvc wine-model-store -n "${NS}" -o wide

echo
echo "==> 7. Enterprise rollout idea"
cat <<'TEXT'
For a new model version:

  1. Upload new artifact to immutable path:
       s3://company-ml-models/wine-quality/1.0.1/model.joblib

  2. Change only storageUri/model-version label in Git:
       storageUri: s3://company-ml-models/wine-quality/1.0.1/

  3. Let GitOps apply the YAML:
       Argo CD / Flux applies the changed InferenceService.

  4. Watch KServe reconcile:
       kubectl get isvc wine-quality -n ml-serving -w

  5. Roll back by reverting Git to the previous storageUri.

This is the enterprise discipline: model deployments are versioned,
reviewed, audited, and reproducible.
TEXT

