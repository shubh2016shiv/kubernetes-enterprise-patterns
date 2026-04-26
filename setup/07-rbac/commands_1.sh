#!/usr/bin/env bash
# =============================================================================
# FILE:    commands.sh
# PURPOSE: Apply RBAC objects and prove least-privilege behavior with
#          kubectl auth can-i checks.
# USAGE:   bash setup/07-rbac/commands.sh
# WHEN:    Run after setup/06-configmaps-secrets so the learner understands why
#          ConfigMap access and Secret access must be treated differently.
# PREREQS: Namespaces `applications` and `monitoring` exist; kubectl points at
#          the kind learning cluster.
# OUTPUT:  Namespace-scoped and cluster-scoped RBAC objects exist; allowed and
#          denied authorization checks behave as expected.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify required namespaces exist before creating RBAC bindings.
#
# Stage 2: Apply Namespace-Scoped RBAC
#   - Create a ServiceAccount, Role, and RoleBinding in applications.
#
# Stage 3: Test Application ServiceAccount Permissions
#   - Prove safe reads are allowed and sensitive or destructive actions are denied.
#
# Stage 4: Apply Cluster-Scoped Monitoring RBAC
#   - Create a ClusterRole and bind it to the monitoring ServiceAccount.
#
# Stage 5: Inspect RBAC State
#   - Show the objects an operator would inspect during troubleshooting.
#
# Stage 6: Debugging Runbook
#   - Leave the learner with the RBAC checks used in real incidents.
# ---------------------------------------------------------------------------

# CONFIGURATION EXPLANATION `applications` is the namespace for the app-facing RBAC example. A namespace is a
# named boundary inside one Kubernetes cluster; Role and RoleBinding objects inside it
# only grant permissions inside that boundary unless a ClusterRoleBinding is used.
APP_NAMESPACE="applications"
# CONFIGURATION EXPLANATION `monitoring` is separated from `applications` to model a production platform team
# pattern: observability tools live in their own namespace while collecting read-only
# signals from many application namespaces.
MONITORING_NAMESPACE="monitoring"
# CONFIGURATION EXPLANATION `inference-gateway-observer-sa` is a ServiceAccount, meaning a Kubernetes identity
# for code running in the cluster, not a person. This identity is intentionally used
# to prove read-only application access without allowing Secret reads or pod deletion.
APP_SERVICE_ACCOUNT="inference-gateway-observer-sa"
# CONFIGURATION EXPLANATION `prometheus-scraper-sa` represents a monitoring collector. Monitoring needs broad
# read visibility, but it should still be a named Kubernetes identity so every allowed
# action can be reviewed and audited.
MONITORING_SERVICE_ACCOUNT="prometheus-scraper-sa"
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

can_i() {
  local expected="$1"
  local description="$2"
  shift 2

  echo "${description}"
  echo "\$ kubectl auth can-i $*"
  actual="$(kubectl auth can-i "$@")"
  echo "${actual}"

  if [ "${actual}" != "${expected}" ]; then
    echo "ERROR: expected '${expected}' but got '${actual}'."
    echo "Check Role, RoleBinding, and any extra ClusterRoleBindings for this identity."
    exit 1
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# Stage 1.0: Preflight Checks
# Purpose: Confirm namespace prerequisites before creating bindings.
# Expected input: setup/02-namespaces has already created applications and monitoring.
# Expected output: both namespace checks succeed.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl version --client=true

for namespace in "${APP_NAMESPACE}" "${MONITORING_NAMESPACE}"; do
  if kubectl get namespace "${namespace}" >/dev/null 2>&1; then
    echo "${namespace} namespace exists"
  else
    echo "ERROR: namespace '${namespace}' does not exist."
    echo "Run: bash setup/02-namespaces/apply-namespaces.sh"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Stage 2.0: Apply Namespace-Scoped RBAC
# Purpose: Grant narrow read-only permissions inside applications.
# Expected output: ServiceAccount, Role, and RoleBinding are created or configured.
# ---------------------------------------------------------------------------
section "Stage 2.0: Apply Namespace-Scoped RBAC"

run_cmd kubectl apply -f "${SCRIPT_DIR}/service-account.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/role.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/rolebinding.yaml"

# ---------------------------------------------------------------------------
# Stage 3.0: Test Application ServiceAccount Permissions
# Purpose: Prove least privilege by checking allowed and denied actions.
# Expected output: safe reads return yes; Secret reads and pod deletion return no.
# ---------------------------------------------------------------------------
section "Stage 3.0: Test Application ServiceAccount Permissions"

# CONFIGURATION EXPLANATION `system:serviceaccount:<namespace>:<name>` is the exact username format Kubernetes
# uses when checking a ServiceAccount. Building it here lets `kubectl auth can-i` ask,
# "what could this workload identity do if it ran in the cluster?"
APP_SUBJECT="system:serviceaccount:${APP_NAMESPACE}:${APP_SERVICE_ACCOUNT}"

can_i "yes" "Can observer get pods?" \
  get pods --as="${APP_SUBJECT}" -n "${APP_NAMESPACE}"

can_i "yes" "Can observer list Services?" \
  list services --as="${APP_SUBJECT}" -n "${APP_NAMESPACE}"

can_i "yes" "Can observer get ConfigMaps from the previous module?" \
  get configmaps --as="${APP_SUBJECT}" -n "${APP_NAMESPACE}"

can_i "no" "Can observer get Secrets from the previous module?" \
  get secrets --as="${APP_SUBJECT}" -n "${APP_NAMESPACE}"

can_i "no" "Can observer delete pods?" \
  delete pods --as="${APP_SUBJECT}" -n "${APP_NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 4.0: Apply Cluster-Scoped Monitoring RBAC
# Purpose: Contrast application namespace permissions with platform tool visibility.
# Expected output: ClusterRole and ClusterRoleBinding are created or configured.
# ---------------------------------------------------------------------------
section "Stage 4.0: Apply Cluster-Scoped Monitoring RBAC"

run_cmd kubectl apply -f "${SCRIPT_DIR}/clusterrole.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/clusterrolebinding.yaml"

# CONFIGURATION EXPLANATION This subject string tests the monitoring ServiceAccount exactly as the Kubernetes
# API sees it. That prevents a common production mistake: testing permissions as your
# admin user instead of the workload identity that will actually run.
MONITORING_SUBJECT="system:serviceaccount:${MONITORING_NAMESPACE}:${MONITORING_SERVICE_ACCOUNT}"

can_i "yes" "Can monitoring identity list nodes cluster-wide?" \
  list nodes --as="${MONITORING_SUBJECT}"

can_i "no" "Can monitoring identity delete deployments?" \
  delete deployments --as="${MONITORING_SUBJECT}" -n "${APP_NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 5.0: Inspect RBAC State
# Purpose: Show the objects operators inspect when debugging authorization.
# Expected output: Role, RoleBinding, ClusterRole, and ClusterRoleBinding details.
# ---------------------------------------------------------------------------
section "Stage 5.0: Inspect RBAC State"

run_cmd kubectl describe role gateway-observer -n "${APP_NAMESPACE}"
run_cmd kubectl describe rolebinding gateway-observer-binding -n "${APP_NAMESPACE}"
run_cmd kubectl describe clusterrole prometheus-read-cluster-state
run_cmd kubectl describe clusterrolebinding prometheus-scraper-cluster-read

# ---------------------------------------------------------------------------
# Stage 6.0: RBAC Debugging Runbook
# Purpose: Teach the minimum useful checks for Forbidden errors.
# Expected output: Actionable next steps.
# ---------------------------------------------------------------------------
section "Stage 6.0: RBAC Debugging Runbook"

echo "1. Check what identity is being used:"
echo "   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'"
echo ""
echo "2. Ask the API server directly:"
echo "   kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<service-account> -n <namespace>"
echo ""
echo "3. Inspect the namespace Role:"
echo "   kubectl describe role gateway-observer -n ${APP_NAMESPACE}"
echo ""
echo "4. Inspect the binding subject:"
echo "   kubectl describe rolebinding gateway-observer-binding -n ${APP_NAMESPACE}"
echo ""
echo "5. If access unexpectedly exists, search for extra grants:"
echo "   kubectl get rolebindings,clusterrolebindings -A"
echo ""
echo "Next step:"
echo "  setup/08-resource-management/README.md"
