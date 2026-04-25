#!/usr/bin/env bash
# =============================================================================
# FILE:    commands.sh
# PURPOSE: Apply ConfigMaps and Secrets, deploy a consumer pod, and verify both
#          environment-variable and mounted-file injection patterns.
# USAGE:   bash setup/06-configmaps-secrets/commands.sh
# WHEN:    Run after setup/05-services so the learner already understands the
#          backend Service DNS name used in the ConfigMap.
# PREREQS: Namespace `applications` exists and kubectl points at the kind
#          learning cluster from setup/01-cluster-setup.
# OUTPUT:  ConfigMap, Secret, and config-demo pod exist; env vars and mounted
#          files prove that configuration was injected successfully.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify kubectl works and the applications namespace exists.
#
# Stage 2: Apply ConfigMap and Secret
#   - Create non-sensitive runtime config and fake learning-only credentials.
#
# Stage 3: Deploy Consumer Pod
#   - Create config-demo and wait until Kubernetes marks it Ready.
#
# Stage 4: Verify Environment Variables
#   - Print safe config values and confirm secret variables exist without
#     leaking their values.
#
# Stage 5: Verify Mounted Files
#   - Read the mounted ConfigMap file and list Secret files without printing
#     password contents.
#
# Stage 6: Debugging Runbook
#   - Leave a production-style checklist for broken config injection.
# ---------------------------------------------------------------------------

NAMESPACE="applications"
POD_NAME="config-demo"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "\$ $*"
  "$@"
  echo ""
}

# ---------------------------------------------------------------------------
# Stage 1.0: Preflight Checks
# Purpose: Fail early with useful guidance before applying any manifests.
# Expected input: kubectl can reach the cluster and namespace exists.
# Expected output: Namespace lookup succeeds.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl version --client=true

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "applications namespace exists"
else
  echo "ERROR: namespace '${NAMESPACE}' does not exist."
  echo "Run the earlier setup modules first, especially setup/02-namespaces."
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Stage 2.0: Apply ConfigMap and Secret
# Purpose: Create the two configuration sources before any pod references them.
# Expected output: ConfigMap and Secret are created or configured.
# ---------------------------------------------------------------------------
section "Stage 2.0: Apply ConfigMap and Secret"

run_cmd kubectl apply -f "${SCRIPT_DIR}/app-configmap.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/app-secret.yaml"

echo "Secret values were applied but not printed. That is intentional."

# ---------------------------------------------------------------------------
# Stage 3.0: Deploy Consumer Pod
# Purpose: Create a pod that references the ConfigMap and Secret.
# Expected output: pod/config-demo is Ready.
# ---------------------------------------------------------------------------
section "Stage 3.0: Deploy Consumer Pod"

run_cmd kubectl apply -f "${SCRIPT_DIR}/pod-using-config.yaml"
run_cmd kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n "${NAMESPACE}" --timeout=90s
run_cmd kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o wide

# ---------------------------------------------------------------------------
# Stage 4.0: Verify Environment Variables
# Purpose: Show safe config values and prove secrets exist without leaking them.
# Expected output: ConfigMap-backed env vars print; Secret values are redacted.
# ---------------------------------------------------------------------------
section "Stage 4.0: Verify Environment Variables"

echo "Safe ConfigMap-backed environment variables:"
run_cmd kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- sh -c \
  'env | grep -E "^(APP_ENV|LOG_LEVEL|RISK_PROFILE_API_BASE_URL|BACKEND_TIMEOUT_MS)=" | sort'

echo "Secret-backed environment variables are present, but values are not printed:"
run_cmd kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- sh -c \
  'test -n "$API_TOKEN" && test -n "$DB_USERNAME" && echo "API_TOKEN and DB_USERNAME are set (values hidden)."'

# ---------------------------------------------------------------------------
# Stage 5.0: Verify Mounted Files
# Purpose: Demonstrate the file-based config and secret consumption pattern.
# Expected output: Config file content is readable; Secret files exist.
# ---------------------------------------------------------------------------
section "Stage 5.0: Verify Mounted Files"

echo "Mounted ConfigMap file:"
run_cmd kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- cat /etc/gateway/config/gateway-runtime.yaml

echo "Mounted Secret filenames and permissions:"
run_cmd kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- ls -l /etc/gateway/secrets

echo "Checking that the password file exists without printing its contents:"
run_cmd kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- sh -c \
  'test -s /etc/gateway/secrets/db-password && echo "db-password file exists and is non-empty (value hidden)."'

# ---------------------------------------------------------------------------
# Stage 6.0: Config Injection Debugging Runbook
# Purpose: Teach the order of checks operators use when config injection fails.
# Expected output: Actionable next steps.
# ---------------------------------------------------------------------------
section "Stage 6.0: Config Injection Debugging Runbook"

echo "1. If the pod does not start:"
echo "   kubectl describe pod ${POD_NAME} -n ${NAMESPACE}"
echo ""
echo "2. If a ConfigMap key is missing:"
echo "   kubectl describe configmap inference-gateway-runtime-config -n ${NAMESPACE}"
echo ""
echo "3. If a Secret key is missing:"
echo "   kubectl describe secret inference-gateway-runtime-secrets -n ${NAMESPACE}"
echo ""
echo "4. If config changed but env vars did not:"
echo "   delete or restart the pod; env vars are fixed at container startup."
echo ""
echo "5. If mounted files changed but the app still uses old values:"
echo "   verify the file updated, then confirm the app rereads config files."
echo ""
echo "Next step:"
echo "  setup/07-rbac/README.md"
