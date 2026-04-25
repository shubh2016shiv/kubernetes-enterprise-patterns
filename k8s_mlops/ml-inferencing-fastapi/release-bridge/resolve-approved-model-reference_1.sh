#!/usr/bin/env bash
# =============================================================================
# FILE:    resolve-approved-model-reference_1.sh
# PURPOSE: Call the MLflow Model Registry REST API to find out which version
#          number the @champion alias currently points to. Write the resolved
#          immutable reference to resolved_model_reference.env so subsequent
#          release bridge scripts can consume it.
# USAGE:   From WSL2, inside release-bridge/:
#            bash resolve-approved-model-reference.sh
#          Or with overrides:
#            MLFLOW_TRACKING_URI=http://mlflow.internal:5000 \
#            MODEL_REGISTRY_NAME=wine-quality-classifier-prod \
#            MODEL_ALIAS=champion \
#            bash resolve-approved-model-reference.sh
# WHEN:    First step of the release bridge. Run after a manager has set the
#          @champion alias in MLflow and before rendering the ConfigMap.
# PREREQS: MLflow server running and reachable. Model has champion alias set.
#          curl and python3 available in WSL2 (both are standard in Ubuntu).
# OUTPUT:  resolved_model_reference.env with MODEL_VERSION and MODEL_URI.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     RELEASE BRIDGE FLOW — Step 1                         │
# │                                                                          │
# │  Stage 1: Read configuration                                             │
# │      └── MLFLOW_TRACKING_URI, MODEL_REGISTRY_NAME, MODEL_ALIAS          │
# │                                                                          │
# │  Stage 2: Confirm MLflow server is listening                            │
# │      └── GET /                                                           │
# │                                                                          │
# │  Stage 3: Call MLflow Model Registry REST API                           │
# │      └── GET /api/2.0/mlflow/registered-models/alias                    │
# │                                                                          │
# │  Stage 3: Extract version number from JSON response                     │
# │      └── model_version.version → "1"                                    │
# │                                                                          │
# │  Stage 4: Construct immutable model URI                                  │
# │      └── models:/wine-quality-classifier-prod/1                          │
# │                                                                          │
# │  Stage 5: Write resolved_model_reference.env                            │
# │      └── MODEL_VERSION=1                                                 │
# │          MODEL_URI=models:/wine-quality-classifier-prod/1                │
# │          MODEL_REGISTRY_NAME=wine-quality-classifier-prod                │
# └─────────────────────────────────────────────────────────────────────────┘

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/resolved_model_reference.env"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1.0: Read configuration
# Priority: environment variable > default value.
# In CI/CD, the pipeline sets these before calling this script.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Release Bridge — Step 1: Resolve Approved Model Reference"
echo "========================================================"

# CAN BE CHANGED: Point this to a different MLflow Tracking Server if your
# local lab or enterprise environment does not use port 5000. Example:
# `http://mlflow.platform.svc.cluster.local:5000`. If changed, keep it aligned
# with the MLflow server started by
# `k8s_mlops/ml-training/training-control-plane/start-mlflow-server.sh` or the
# equivalent enterprise MLflow endpoint used by your CI/CD pipeline.
MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://127.0.0.1:5000}"
MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI%/}"

# CAN BE CHANGED: This must match the production-approved registered model name
# created in `k8s_mlops/ml-training/training-control-plane/mlflow-manager-promotion-runbook.md`.
# Example: `fraud-risk-classifier-prod`. If changed, update the manager runbook,
# `render-inference-config.sh`, and any Kubernetes ConfigMap field that expects
# the same registered model lineage.
MODEL_REGISTRY_NAME="${MODEL_REGISTRY_NAME:-wine-quality-classifier-prod}"

# CAN BE CHANGED: This must match the alias assigned by the manager or approval
# workflow in MLflow. Example: `challenger` for a canary test. If changed, update
# the manager promotion runbook and the serving handoff documentation so humans
# and automation agree on the approved alias name.
MODEL_ALIAS="${MODEL_ALIAS:-champion}"

echo "  MLFLOW_TRACKING_URI:  ${MLFLOW_TRACKING_URI}"
echo "  MODEL_REGISTRY_NAME:  ${MODEL_REGISTRY_NAME}"
echo "  MODEL_ALIAS:          ${MODEL_ALIAS}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2.0: Preflight — confirm MLflow is reachable
# Why: This checks that the MLflow web server is listening before we make the
#      model-registry-specific alias request. Older versions of this script used
#      `/api/2.0/mlflow/experiments/list`, but MLflow 3.x can return HTTP 404
#      for that retired endpoint even when the server and registry are healthy.
#      A root-page check keeps the connectivity test about connectivity, then
#      Stage 3 validates the exact Model Registry API we need.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Stage 2: Checking MLflow connectivity ---"

HEALTH_CHECK_URL="${MLFLOW_TRACKING_URI}/"

HTTP_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  "${HEALTH_CHECK_URL}" \
  --max-time 5 2>/dev/null || echo "unreachable")

if [[ "${HTTP_CHECK}" != "200" && "${HTTP_CHECK}" != "304" ]]; then
  echo "✗ MLflow server is not reachable at ${MLFLOW_TRACKING_URI} (HTTP ${HTTP_CHECK})."
  echo ""
  echo "  If MLflow runs on your WSL2 host:"
  echo "    cd k8s_mlops/ml-training/training-control-plane"
  echo "    ./start-mlflow-server.sh"
  echo "  Then retry this script."
  exit 1
fi
echo "✓ MLflow server reachable (HTTP ${HTTP_CHECK})."

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3.0: Call the MLflow alias resolution API
# API reference: GET /api/2.0/mlflow/registered-models/alias
# Parameters: name (registered model name), alias (alias name)
# Response: ModelVersion JSON with .model_version.version field
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 3: Resolving alias '${MODEL_ALIAS}' for '${MODEL_REGISTRY_NAME}' ---"

# URL-encode learner-controlled values before putting them into a query string.
# Why: A model name such as `fraud risk classifier prod` contains spaces, and an
# alias could contain characters that have special meaning in URLs. Passing the
# values as Python arguments avoids shell-quoting surprises.
ENCODED_NAME=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${MODEL_REGISTRY_NAME}")
ENCODED_ALIAS=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${MODEL_ALIAS}")

ALIAS_API_URL="${MLFLOW_TRACKING_URI}/api/2.0/mlflow/registered-models/alias?name=${ENCODED_NAME}&alias=${ENCODED_ALIAS}"

echo "  Calling: GET ${ALIAS_API_URL}"

ALIAS_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${ALIAS_API_URL}" \
  --max-time 10 2>/dev/null)

ALIAS_HTTP_STATUS=$(echo "${ALIAS_RESPONSE}" | tail -1)
ALIAS_BODY=$(echo "${ALIAS_RESPONSE}" | head -n -1)

if [[ "${ALIAS_HTTP_STATUS}" != "200" ]]; then
  echo "✗ MLflow alias API returned HTTP ${ALIAS_HTTP_STATUS}."
  echo "  Response body: ${ALIAS_BODY}"
  echo ""
  echo "  Possible causes:"
  echo "    - Registered model '${MODEL_REGISTRY_NAME}' does not exist in MLflow."
  echo "      Create it by promoting a candidate via the MLflow UI or manager runbook."
  echo "    - Alias '${MODEL_ALIAS}' has not been set on any version."
  echo "      Run the manager promotion runbook to assign the champion alias."
  echo "    - The registered model name is misspelled."
  echo "      Check: ${MLFLOW_TRACKING_URI}/#/models"
  exit 1
fi

echo "✓ MLflow returned HTTP 200."

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4.0: Extract the version number from the JSON response
# The response structure is: {"model_version": {"version": "1", ...}}
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 4: Extracting version number from response ---"

VERSION_NUMBER=$(python3 -c "
import json, sys
data = json.loads('''${ALIAS_BODY}''')
version = data.get('model_version', {}).get('version', '')
if not version:
    print('ERROR: version field not found in response', file=sys.stderr)
    sys.exit(1)
print(version)
" 2>/dev/null || echo "")

if [[ -z "${VERSION_NUMBER}" ]]; then
  echo "✗ Could not extract version number from MLflow response."
  echo "  Raw response: ${ALIAS_BODY}"
  echo "  Expected JSON field: .model_version.version"
  exit 1
fi

echo "✓ Alias '${MODEL_ALIAS}' resolves to version: ${VERSION_NUMBER}"

# Construct the immutable model URI. This is what FastAPI will load.
IMMUTABLE_MODEL_URI="models:/${MODEL_REGISTRY_NAME}/${VERSION_NUMBER}"
echo "  Immutable model URI: ${IMMUTABLE_MODEL_URI}"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 5.0: Write the resolved reference to a file
# The next release bridge scripts (render-inference-config.sh and
# rollout-approved-model.sh) source this file to get MODEL_VERSION and MODEL_URI.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 5: Writing resolved_model_reference.env ---"

RESOLVED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "${OUTPUT_FILE}" <<EOF
# Generated by resolve-approved-model-reference.sh at ${RESOLVED_AT}
# Source this file in subsequent release bridge steps:
#   source resolved_model_reference.env
MODEL_REGISTRY_NAME=${MODEL_REGISTRY_NAME}
MODEL_ALIAS=${MODEL_ALIAS}
MODEL_VERSION=${VERSION_NUMBER}
MODEL_URI=${IMMUTABLE_MODEL_URI}
MLFLOW_TRACKING_URI=${MLFLOW_TRACKING_URI}
RESOLVED_AT=${RESOLVED_AT}
EOF

echo "✓ Written to: ${OUTPUT_FILE}"
echo "  Contents:"
cat "${OUTPUT_FILE}" | sed 's/^/    /'

echo ""
echo "========================================================"
echo "  ✓ Step 1 complete."
echo "  Alias @${MODEL_ALIAS} resolved to version ${VERSION_NUMBER}."
echo "  Immutable URI: ${IMMUTABLE_MODEL_URI}"
echo ""
echo "  Next step:"
echo "    bash render-inference-config.sh"
echo "========================================================"
