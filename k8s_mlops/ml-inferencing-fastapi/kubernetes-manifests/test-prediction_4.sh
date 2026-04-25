#!/usr/bin/env bash
# =============================================================================
# FILE:    test-prediction_4.sh
# PURPOSE: Run a release smoke test through the Kubernetes Service and verify
#          that the inference API returns the expected prediction from the exact
#          model version recorded in the ConfigMap.
# USAGE:   From WSL2, inside kubernetes-manifests/:
#            bash test-prediction.sh
# WHEN:    Run after apply-inference-stack_3.sh, after every model rollout, and
#          from rollout-approved-model.sh before declaring a release complete.
# PREREQS: Inference stack deployed, Service has ready endpoints, and the
#          ConfigMap contains resolved MODEL_URI and MODEL_VERSION values.
# OUTPUT:  Exit 0 only when health, response schema, prediction class, and
#          served model identity all match the deployed release config.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────┐
# │                    SMOKE TEST FLOW                                  │
# │                                                                     │
# │  Stage 1: Read Expected Release Config                              │
# │      └── MODEL_URI and MODEL_VERSION from ConfigMap                  │
# │                                                                     │
# │  Stage 2: Verify Service Endpoints                                  │
# │      └── Service must route to ready pods, not arbitrary Running pods│
# │                                                                     │
# │  Stage 3: Port-forward Through Service                              │
# │      └── Test the same stable endpoint callers use                   │
# │                                                                     │
# │  Stage 4: Health Gate                                               │
# │      └── /health/ready must return HTTP 200                          │
# │                                                                     │
# │  Stage 5: Prediction Contract Check                                 │
# │      └── Assert class, label, MODEL_URI, and MODEL_VERSION           │
# └─────────────────────────────────────────────────────────────────────┘

# CAN BE CHANGED: Must match 01-namespace.yaml. Example:
# `NAMESPACE="ml-inference-dev"` if you renamed the namespace.
NAMESPACE="ml-inference"
# CAN BE CHANGED: Must match 06-inference-service.yaml metadata.name.
# Example: `SERVICE_NAME="fraud-risk-inference-service"`.
SERVICE_NAME="wine-quality-inference-service"
# CAN BE CHANGED: Must match 02-inference-configmap.yaml metadata.name.
# Example: `CONFIGMAP_NAME="fraud-risk-inference-config"`.
CONFIGMAP_NAME="wine-quality-inference-config"
# CAN BE CHANGED: Local laptop port used for `kubectl port-forward`.
# Example: `LOCAL_PORT=19081` if 18081 is already in use.
LOCAL_PORT=18081
# CAN BE CHANGED: Expected prediction for the smoke-test fixture below. Change
# this only when the model, labels, or sample payload changes. Example: `"1"`.
EXPECTED_CLASS="0"
# CAN BE CHANGED: Must match the label returned by the model for the fixture.
# Example: `"approved"` for a binary approval model.
EXPECTED_LABEL="class_0"

# A known wine sample from the UCI Wine dataset (sample index 0, class 0).
# This is a smoke-test fixture, not a full model evaluation suite. Its job is to
# catch broken serving contracts after deployment: wrong model, wrong schema,
# not-ready pods, or unexpected prediction behavior.
# CAN BE CHANGED: Replace this JSON with a known-good request for your model.
# Keep EXPECTED_CLASS and EXPECTED_LABEL aligned with the new payload.
SAMPLE_PAYLOAD='{
  "alcohol": 14.23,
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
}'

print_diagnostics() {
  echo ""
  echo "Diagnostics:"
  echo "  kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=wine-quality-inference-api -o wide"
  echo "  kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE} -o yaml"
  echo "  kubectl get configmap ${CONFIGMAP_NAME} -n ${NAMESPACE} -o yaml"
  echo "  kubectl logs -l app.kubernetes.io/name=wine-quality-inference-api -n ${NAMESPACE} --tail=100"
}

fail() {
  echo "✗ $1"
  print_diagnostics
  exit 1
}

echo ""
echo "========================================================"
echo "  Inference API - Release Smoke Test"
echo "========================================================"
echo "  Namespace: ${NAMESPACE}"
echo "  Service:   ${SERVICE_NAME}"
echo "  Fixture:   UCI Wine dataset sample 0"
echo "  Expected:  predicted_class=${EXPECTED_CLASS}, predicted_label=${EXPECTED_LABEL}"
echo ""

# ─────────────────────────────────────────────────────────
# Stage 1.0: Read Expected Release Config
# Purpose: A smoke test must know which model version the release intended to
#          deploy. Otherwise it can accidentally pass against an old pod.
# ─────────────────────────────────────────────────────────
echo "--- Stage 1: Reading expected model identity from ConfigMap ---"

EXPECTED_MODEL_URI=$(kubectl get configmap "${CONFIGMAP_NAME}" \
  -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_URI}' 2>/dev/null || true)
EXPECTED_MODEL_VERSION=$(kubectl get configmap "${CONFIGMAP_NAME}" \
  -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_VERSION}' 2>/dev/null || true)

if [[ -z "${EXPECTED_MODEL_URI}" ]] || [[ "${EXPECTED_MODEL_URI}" == "REPLACE_WITH_RESOLVED_URI" ]]; then
  fail "ConfigMap MODEL_URI is missing or still has the placeholder value."
fi

if [[ -z "${EXPECTED_MODEL_VERSION}" ]] || [[ "${EXPECTED_MODEL_VERSION}" == "REPLACE_WITH_VERSION_NUMBER" ]]; then
  fail "ConfigMap MODEL_VERSION is missing or still has the placeholder value."
fi

echo "✓ Expected MODEL_URI:     ${EXPECTED_MODEL_URI}"
echo "✓ Expected MODEL_VERSION: ${EXPECTED_MODEL_VERSION}"

# ─────────────────────────────────────────────────────────
# Stage 2.0: Verify Service Endpoints
# Purpose: Test the Service path, not one arbitrary Running pod. Kubernetes
#          Services route only to pods that match labels and pass readiness.
# ─────────────────────────────────────────────────────────
echo ""
echo "--- Stage 2: Confirming Service has ready endpoints ---"

READY_ENDPOINTS=$(kubectl get endpoints "${SERVICE_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)

if [[ -z "${READY_ENDPOINTS}" ]]; then
  fail "Service has no ready endpoints. Pods may be running but not ready."
fi

echo "✓ Service has ready endpoint IPs: ${READY_ENDPOINTS}"

# ─────────────────────────────────────────────────────────
# Stage 3.0: Port-forward Through Service
# Purpose: Port-forward through the stable Service endpoint so the smoke test
#          validates the same traffic path used by internal callers.
# ─────────────────────────────────────────────────────────
echo ""
echo "--- Stage 3: Starting port-forward (local port ${LOCAL_PORT} -> service port 8080) ---"

# CAN BE CHANGED: The right-hand side `8080` must match the Service `port` in
# 06-inference-service.yaml. Example: `"${LOCAL_PORT}":80` if Service port is 80.
kubectl port-forward "service/${SERVICE_NAME}" "${LOCAL_PORT}":8080 -n "${NAMESPACE}" >/tmp/wine-quality-inference-port-forward.log 2>&1 &
PF_PID=$!

cleanup() {
  kill "${PF_PID}" 2>/dev/null || true
  wait "${PF_PID}" 2>/dev/null || true
}
trap cleanup EXIT

sleep 2

if ! kill -0 "${PF_PID}" 2>/dev/null; then
  echo "Port-forward log:"
  sed 's/^/  /' /tmp/wine-quality-inference-port-forward.log 2>/dev/null || true
  fail "Port-forward to Service failed."
fi

echo "✓ Port-forward established through Service."

# ─────────────────────────────────────────────────────────
# Stage 4.0: Health Gate
# Purpose: Readiness must prove the model is loaded before /predict is tested.
# ─────────────────────────────────────────────────────────
echo ""
echo "--- Stage 4: Confirming readiness through Service ---"

READY_STATUS=$(curl -s -o /tmp/wine-quality-ready-response.json -w "%{http_code}" \
  "http://127.0.0.1:${LOCAL_PORT}/health/ready" 2>/dev/null || echo "unreachable")

if [[ "${READY_STATUS}" != "200" ]]; then
  echo "Readiness response:"
  sed 's/^/  /' /tmp/wine-quality-ready-response.json 2>/dev/null || true
  fail "Service readiness check returned HTTP ${READY_STATUS}; expected HTTP 200."
fi

echo "✓ Service readiness returned HTTP 200."

# ─────────────────────────────────────────────────────────
# Stage 5.0: Prediction Contract Check
# Purpose: Validate behavior, not only response shape. This catches wrong model
#          versions, stale pods, and accidental API/schema regressions.
# ─────────────────────────────────────────────────────────
echo ""
echo "--- Stage 5: Sending prediction request and validating release contract ---"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "http://127.0.0.1:${LOCAL_PORT}/predict" \
  -H "Content-Type: application/json" \
  -d "${SAMPLE_PAYLOAD}" 2>/dev/null)

HTTP_STATUS=$(echo "${RESPONSE}" | tail -1)
RESPONSE_BODY=$(echo "${RESPONSE}" | head -n -1)

echo "  HTTP status: ${HTTP_STATUS}"
echo "  Response body:"
echo "${RESPONSE_BODY}" | sed 's/^/    /'

if [[ "${HTTP_STATUS}" != "200" ]]; then
  fail "Prediction endpoint returned HTTP ${HTTP_STATUS}; expected HTTP 200."
fi

python3 - \
  "${RESPONSE_BODY}" \
  "${EXPECTED_CLASS}" \
  "${EXPECTED_LABEL}" \
  "${EXPECTED_MODEL_URI}" \
  "${EXPECTED_MODEL_VERSION}" <<'EOF'
import json
import sys

body = json.loads(sys.argv[1])
expected_class = int(sys.argv[2])
expected_label = sys.argv[3]
expected_uri = sys.argv[4]
expected_version = sys.argv[5]

required_fields = [
    "predicted_class",
    "predicted_label",
    "served_model_uri",
    "model_version",
    "registry_name",
]
missing = [field for field in required_fields if field not in body]
if missing:
    raise SystemExit(f"missing required response fields: {missing}")

checks = {
    "predicted_class": body["predicted_class"] == expected_class,
    "predicted_label": body["predicted_label"] == expected_label,
    "served_model_uri": body["served_model_uri"] == expected_uri,
    "model_version": str(body["model_version"]) == expected_version,
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit(
        "release contract mismatch: "
        + ", ".join(failed)
        + f"; response={body!r}"
    )

print("✓ Response schema, prediction, and model identity match expected release config.")
EOF

echo ""
echo "========================================================"
echo "  ✓ Smoke test passed."
echo "  The Service is routing to ready pods serving ${EXPECTED_MODEL_URI}."
echo "========================================================"

# ANTI-PATTERN TO AVOID: A smoke test that only checks for HTTP 200 or field
# names can pass while the wrong model version is serving. Enterprise release
# gates must validate the deployed model identity and at least one known
# prediction fixture before declaring the rollout complete.
