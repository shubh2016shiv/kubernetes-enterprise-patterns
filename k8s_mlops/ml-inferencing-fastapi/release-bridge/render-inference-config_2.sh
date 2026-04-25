#!/usr/bin/env bash
# =============================================================================
# FILE:    render-inference-config_2.sh
# PURPOSE: Read the resolved model reference from resolved_model_reference.env
#          and update kubernetes-manifests/02-inference-configmap.yaml with the
#          immutable MODEL_URI, MODEL_VERSION, and related deployment metadata.
#          Also updates the Deployment manifest labels and annotations.
# USAGE:   From WSL2, inside release-bridge/:
#            bash render-inference-config.sh
# WHEN:    Second step of the release bridge. Run after resolve-approved-model-reference.sh
#          produces resolved_model_reference.env.
# PREREQS: resolved_model_reference.env exists in this directory.
# OUTPUT:  02-inference-configmap.yaml and 05-inference-deployment.yaml updated
#          with the resolved model version. Manifests are ready for kubectl apply.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     RELEASE BRIDGE FLOW — Step 2                         │
# │                                                                          │
# │  Stage 1: Load resolved reference from .env file                        │
# │                                                                          │
# │  Stage 2: Patch 02-inference-configmap.yaml                             │
# │      └── Replace MODEL_URI placeholder with resolved version URI        │
# │      └── Replace MODEL_VERSION placeholder with version number          │
# │      └── Update last-updated annotation                                 │
# │                                                                          │
# │  Stage 3: Patch 05-inference-deployment.yaml                            │
# │      └── Update model-version labels on Deployment and PodTemplate      │
# │      └── Update checksum/config annotation (triggers rollout on apply)  │
# └─────────────────────────────────────────────────────────────────────────┘

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../kubernetes-manifests"
ENV_FILE="${SCRIPT_DIR}/resolved_model_reference.env"

echo ""
echo "========================================================"
echo "  Release Bridge — Step 2: Render Kubernetes Config"
echo "========================================================"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1.0: Load resolved reference
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 1: Loading resolved_model_reference.env ---"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "✗ ${ENV_FILE} not found."
  echo "  Run resolve-approved-model-reference.sh first."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

echo "✓ Loaded:"
echo "  MODEL_URI:            ${MODEL_URI}"
echo "  MODEL_VERSION:        ${MODEL_VERSION}"
echo "  MODEL_REGISTRY_NAME:  ${MODEL_REGISTRY_NAME}"
echo "  RESOLVED_AT:          ${RESOLVED_AT}"

# Validate that the values are not empty placeholders.
if [[ "${MODEL_URI}" == "REPLACE_WITH_RESOLVED_URI" ]] || [[ -z "${MODEL_URI}" ]]; then
  echo "✗ MODEL_URI is a placeholder or empty. resolve-approved-model-reference.sh may have failed."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2.0: Patch the ConfigMap manifest
# Uses sed to replace placeholder values with resolved ones.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 2: Patching 02-inference-configmap.yaml ---"

CONFIGMAP_FILE="${MANIFESTS_DIR}/02-inference-configmap.yaml"

if [[ ! -f "${CONFIGMAP_FILE}" ]]; then
  echo "✗ ${CONFIGMAP_FILE} not found."
  echo "  Ensure the kubernetes-manifests/ directory is intact."
  exit 1
fi

# Create a backup of the current ConfigMap before patching.
cp "${CONFIGMAP_FILE}" "${CONFIGMAP_FILE}.bak"
echo "  Backup created: ${CONFIGMAP_FILE}.bak"

# Patch MODEL_URI placeholder.
sed -i "s|MODEL_URI: \"REPLACE_WITH_RESOLVED_URI\"|MODEL_URI: \"${MODEL_URI}\"|g" "${CONFIGMAP_FILE}"
# Patch MODEL_VERSION placeholder.
sed -i "s|MODEL_VERSION: \"REPLACE_WITH_VERSION_NUMBER\"|MODEL_VERSION: \"${MODEL_VERSION}\"|g" "${CONFIGMAP_FILE}"
# Patch the last-updated annotation.
sed -i "s|mlops.platform/last-updated: \"YYYY-MM-DDTHH:MM:SSZ\"|mlops.platform/last-updated: \"${RESOLVED_AT}\"|g" "${CONFIGMAP_FILE}"

# Also patch in case the values were already set from a prior run (re-release).
# This replaces any existing MODEL_URI value (already resolved) with the new one.
python3 - "${CONFIGMAP_FILE}" "${MODEL_URI}" "${MODEL_VERSION}" "${RESOLVED_AT}" <<'EOF'
import sys, re

filepath = sys.argv[1]
new_uri  = sys.argv[2]
new_ver  = sys.argv[3]
new_ts   = sys.argv[4]

with open(filepath, "r") as f:
    content = f.read()

# Replace MODEL_URI line value (handles both placeholder and previously-set values).
# ENTERPRISE EMPHASIS: Use lambda replacements instead of `\1${value}\2`.
# Why: model versions often start with digits. In Python regex replacement
# strings, `\1` followed by `1` becomes `\11`, which means "group 11" and fails.
content = re.sub(
    r'(  MODEL_URI:\s+")[^"]*(")',
    lambda match: f'{match.group(1)}{new_uri}{match.group(2)}',
    content
)
# Replace MODEL_VERSION line value
content = re.sub(
    r'(  MODEL_VERSION:\s+")[^"]*(")',
    lambda match: f'{match.group(1)}{new_ver}{match.group(2)}',
    content
)
# Replace last-updated annotation
content = re.sub(
    r'(mlops\.platform/last-updated:\s+")[^"]*(")',
    lambda match: f'{match.group(1)}{new_ts}{match.group(2)}',
    content
)

with open(filepath, "w") as f:
    f.write(content)

print("ConfigMap patched successfully.")
EOF

echo "✓ ConfigMap patched:"
echo "  MODEL_URI     →  ${MODEL_URI}"
echo "  MODEL_VERSION →  ${MODEL_VERSION}"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3.0: Patch the Deployment manifest labels and config checksum
# The checksum annotation triggers a rolling restart when kubectl apply is run,
# even if only the ConfigMap changed and not the Deployment spec itself.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 3: Patching 05-inference-deployment.yaml ---"

DEPLOY_FILE="${MANIFESTS_DIR}/05-inference-deployment.yaml"

if [[ ! -f "${DEPLOY_FILE}" ]]; then
  echo "✗ ${DEPLOY_FILE} not found."
  exit 1
fi

cp "${DEPLOY_FILE}" "${DEPLOY_FILE}.bak"

# Compute a checksum of the updated ConfigMap content.
# This value is written into the Deployment's pod template annotation.
# Kubernetes detects the annotation change as a spec change and triggers rollout.
CONFIG_CHECKSUM=$(sha256sum "${CONFIGMAP_FILE}" | awk '{print $1}')

python3 - "${DEPLOY_FILE}" "${MODEL_VERSION}" "${CONFIG_CHECKSUM}" <<'EOF'
import sys, re

filepath = sys.argv[1]
new_ver   = sys.argv[2]
checksum  = sys.argv[3]

with open(filepath, "r") as f:
    content = f.read()

# Update model-version label on Deployment metadata and pod template metadata.
# ENTERPRISE EMPHASIS: Use lambda replacements instead of numeric backreference
# strings so model version `1`, `10`, or any other digit-starting value cannot
# be misread by Python regex as an invalid capture group reference.
content = re.sub(
    r'(mlops\.platform/model-version:\s+")[^"]*(")',
    lambda match: f'{match.group(1)}{new_ver}{match.group(2)}',
    content
)
# Update checksum/config annotation.
content = re.sub(
    r'(checksum/config:\s+")[^"]*(")',
    lambda match: f'{match.group(1)}{checksum}{match.group(2)}',
    content
)

with open(filepath, "w") as f:
    f.write(content)

print("Deployment patched successfully.")
EOF

echo "✓ Deployment patched:"
echo "  model-version label  →  ${MODEL_VERSION}"
echo "  checksum/config      →  ${CONFIG_CHECKSUM:0:16}..."

echo ""
echo "========================================================"
echo "  ✓ Step 2 complete. Kubernetes manifests updated."
echo ""
echo "  The ConfigMap and Deployment now reference:"
echo "    MODEL_URI:     ${MODEL_URI}"
echo "    MODEL_VERSION: ${MODEL_VERSION}"
echo ""
echo "  Next step:"
echo "    bash rollout-approved-model.sh"
echo "========================================================"
