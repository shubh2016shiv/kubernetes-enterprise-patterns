#!/usr/bin/env bash
# =============================================================================
# FILE:    rotate-database-password.sh
# PURPOSE: Rotate the application database password and restart API pods.
# USAGE:   NEW_DATABASE_PASSWORD='new-local-password' bash app_k8_deployment/deployment-lifecycle/rotate-database-password.sh
# WHEN:    Run to learn how Secret changes become live pod configuration.
# PREREQS: Database pod is Ready and NEW_DATABASE_PASSWORD is set.
# OUTPUT:  Database user password, Kubernetes Secret, and API pods are updated.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify required env var and database pod.
#
# Stage 2: Rotate Database User Password
#   - ALTER USER inside MariaDB.
#
# Stage 3: Update Kubernetes Secret
#   - Store the new password without printing it.
#
# Stage 4: Restart Backend Pods
#   - Force pods to read the updated Secret value.
#
# Stage 5: Verify Readiness
#   - Wait for readiness-gated rollout completion.
# ---------------------------------------------------------------------------

# CONFIGURATION EXPLANATION This namespace contains both the Kubernetes Secret and the database pod. The Secret
# stores the password value for new API pods, while the database pod owns the actual database user password; both
# must be updated together during rotation.
NAMESPACE="patient-record-system"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "$ $*"
  "$@"
  echo ""
}

# ---------------------------------------------------------------------------
# Stage 1.0: Preflight Checks
# Purpose: Avoid printing or guessing a secret value.
# Expected input: NEW_DATABASE_PASSWORD is set by the operator.
# Expected output: Database pod exists and required Secret is readable.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

if [[ -z "${NEW_DATABASE_PASSWORD:-}" ]]; then
  echo "ERROR: Set NEW_DATABASE_PASSWORD before running this script."
  echo "Example: NEW_DATABASE_PASSWORD='new-local-password' bash app_k8_deployment/deployment-lifecycle/rotate-database-password.sh"
  exit 1
fi

if [[ "${NEW_DATABASE_PASSWORD}" == *"'"* ]]; then
  echo "ERROR: NEW_DATABASE_PASSWORD must not contain a single quote for this learning script."
  echo "Enterprise rotation tooling should pass credentials through safer secret-management APIs."
  exit 1
fi

run_cmd kubectl get pod patient-record-database-0 -n "${NAMESPACE}"

# CONFIGURATION EXPLANATION The database name is read from the existing Secret so rotation updates credentials
# without accidentally changing which schema the application uses.
DATABASE_NAME="$(kubectl get secret patient-record-database-credentials -n "${NAMESPACE}" -o jsonpath='{.data.mysql-database}' | base64 -d)"
# CONFIGURATION EXPLANATION The database username is read from the Secret to keep the MariaDB user and Kubernetes
# configuration aligned. The script must rotate the password for the same user the API uses.
DATABASE_USER="$(kubectl get secret patient-record-database-credentials -n "${NAMESPACE}" -o jsonpath='{.data.mysql-user}' | base64 -d)"
# CONFIGURATION EXPLANATION The current password is decoded only for the MariaDB command and is never printed.
# That models production handling: secrets may be used by automation, but they should not appear in logs.
CURRENT_PASSWORD="$(kubectl get secret patient-record-database-credentials -n "${NAMESPACE}" -o jsonpath='{.data.mysql-password}' | base64 -d)"

# ---------------------------------------------------------------------------
# Stage 2.0: Rotate Database User Password
# Purpose: Change the actual database credential before changing pod config.
# Expected output: MariaDB accepts ALTER USER.
# ---------------------------------------------------------------------------
section "Stage 2.0: Rotate Database User Password"

echo "ENTERPRISE EMPHASIS: Updating a Kubernetes Secret alone does not rotate the database password. The database credential and the Secret must move together."
kubectl exec patient-record-database-0 -n "${NAMESPACE}" -- \
  mariadb \
    -u"${DATABASE_USER}" \
    -p"${CURRENT_PASSWORD}" \
    "${DATABASE_NAME}" \
    -e "ALTER USER '${DATABASE_USER}'@'%' IDENTIFIED BY '${NEW_DATABASE_PASSWORD}'; FLUSH PRIVILEGES;"
echo "Database password rotated. New value was not printed."

# ---------------------------------------------------------------------------
# Stage 3.0: Update Kubernetes Secret
# Purpose: Update the source used by newly started backend pods.
# Expected output: Secret is updated without echoing password contents.
# ---------------------------------------------------------------------------
section "Stage 3.0: Update Kubernetes Secret"

kubectl create secret generic patient-record-database-credentials \
  --namespace "${NAMESPACE}" \
  --from-literal=mysql-root-password=local-root-password \
  --from-literal=mysql-database="${DATABASE_NAME}" \
  --from-literal=mysql-user="${DATABASE_USER}" \
  --from-literal=mysql-password="${NEW_DATABASE_PASSWORD}" \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

echo "Secret updated. Secret value was not displayed."

# ---------------------------------------------------------------------------
# Stage 4.0: Restart Backend Pods
# Purpose: Environment-variable Secret references update only when pods restart.
# Expected output: Deployment creates replacement pods.
# ---------------------------------------------------------------------------
section "Stage 4.0: Restart Backend Pods"

echo "ENTERPRISE EMPHASIS: Env-var Secrets are captured at container startup. Rollout restart makes pods read the new value."
run_cmd kubectl rollout restart deployment/patient-record-api -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 5.0: Verify Readiness
# Purpose: Ensure the backend can authenticate with the rotated password.
# Expected output: rollout status succeeds and /readyz works.
# ---------------------------------------------------------------------------
section "Stage 5.0: Verify Readiness"

# CONFIGURATION EXPLANATION The 180s timeout proves that restarted API pods can authenticate with the rotated
# password. If readiness fails, traffic should remain blocked instead of serving broken database calls.
run_cmd kubectl rollout status deployment/patient-record-api -n "${NAMESPACE}" --timeout=180s
echo "Run full verification:"
echo "  bash app_k8_deployment/deployment-lifecycle/verify-patient-record-system.sh"
