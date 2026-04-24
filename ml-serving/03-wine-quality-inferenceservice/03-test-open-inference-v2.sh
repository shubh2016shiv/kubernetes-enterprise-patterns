#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/03-wine-quality-inferenceservice/03-test-open-inference-v2.sh
#
# PURPOSE:
#   Send a prediction request to the KServe sklearn runtime.
#
# LOCAL NETWORKING NOTE:
#   In enterprise, external traffic reaches KServe through an Ingress, Gateway,
#   API gateway, service mesh, or internal load balancer.
#
#   Locally, networking varies depending on how Docker Desktop and KServe
#   Gateway/Ingress were installed. The most reliable learner path is port
#   forwarding the generated predictor Service.
#
# FLOW:
#   terminal 1:
#     bash ml-serving/03-wine-quality-inferenceservice/03-test-open-inference-v2.sh
#
# WHAT THE SCRIPT DOES:
#   1. Finds the generated Kubernetes Service.
#   2. Port-forwards it to localhost:8080.
#   3. Sends a V2 inference request.
#   4. Cleans up the port-forward process.
# =============================================================================

set -euo pipefail

NS="ml-serving"
NAME="wine-quality"
REQUEST_FILE="ml-serving/03-wine-quality-inferenceservice/sample-v2-infer.json"

echo "==> Waiting for InferenceService to become Ready"
kubectl wait --for=condition=Ready inferenceservice/"${NAME}" \
  --namespace "${NS}" \
  --timeout=300s

echo "==> Finding generated predictor Service"
SERVICE_NAME="$(kubectl get service -n "${NS}" \
  -l serving.kserve.io/inferenceservice="${NAME}" \
  -o jsonpath='{.items[0].metadata.name}')"

echo "==> Port-forwarding service/${SERVICE_NAME} to localhost:8080"
kubectl port-forward -n "${NS}" "service/${SERVICE_NAME}" 8080:80 >/tmp/kserve-wine-quality-port-forward.log 2>&1 &
PF_PID="$!"

cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 3

echo "==> Calling Open Inference Protocol v2 endpoint"
curl -sS \
  -H "Content-Type: application/json" \
  --data @"${REQUEST_FILE}" \
  "http://127.0.0.1:8080/v2/models/${NAME}/infer"

echo
echo "==> Done"

