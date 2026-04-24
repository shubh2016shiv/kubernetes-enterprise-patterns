#!/usr/bin/env bash
# =============================================================================
# FILE:    deploy-patient-record-system.sh
# PURPOSE: Deploy the full frontend, FastAPI backend, and SQL database stack.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/deploy-patient-record-system.sh
# WHEN:    Run after images are built and loaded into kind.
# PREREQS: kubectl points at kind-local-enterprise-dev and local images exist.
# OUTPUT:  The patient intake UI is reachable at http://localhost:30001.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify kubectl can reach the cluster.
#
# Stage 2: Apply Foundation Manifests
#   - Namespace, resource governance, Secret, ConfigMap, RBAC.
#
# Stage 3: Deploy Database Tier
#   - Services and StatefulSet with persistent storage.
#
# Stage 4: Deploy Backend Tier
#   - Run schema Job, then FastAPI Deployment and ClusterIP Service.
#
# Stage 5: Deploy Frontend Tier
#   - nginx UI Deployment and NodePort Service.
#
# Stage 6: Apply Enterprise Controls
#   - NetworkPolicy, PDB, HPA, Ingress, and backup CronJob.
#
# Stage 7: Show Access and Debug Commands
#   - Print the first operational checks.
# ---------------------------------------------------------------------------

NAMESPACE="patient-record-system"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_DIR="${MODULE_DIR}/kubernetes-manifests"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "$ $*"
  "$@"
  echo ""
}

apply_manifest() {
  run_cmd kubectl apply -f "${MANIFEST_DIR}/$1"
}

# ---------------------------------------------------------------------------
# Stage 1.0: Preflight Checks
# Purpose: Confirm kubectl can talk to the target cluster before applying YAML.
# Expected input: setup/01-cluster-setup has created the kind cluster.
# Expected output: kubectl version and current context are visible.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl version --client=true
run_cmd kubectl config current-context

# ---------------------------------------------------------------------------
# Stage 2.0: Apply Foundation Manifests
# Purpose: Create isolation, resource governance, and runtime configuration.
# Expected output: namespace, LimitRange, ResourceQuota, Secret, and ConfigMap.
# ---------------------------------------------------------------------------
section "Stage 2.0: Apply Foundation Manifests"

apply_manifest "00-namespace.yaml"
apply_manifest "01-resource-governance.yaml"
apply_manifest "02-database-secret.yaml"
apply_manifest "03-backend-configmap.yaml"
apply_manifest "04-access-control-rbac.yaml"

# ---------------------------------------------------------------------------
# Stage 3.0: Deploy Database Tier
# Purpose: Start the persistent SQL tier before the API tries to connect.
# Expected output: StatefulSet reaches ready state and PVC is bound.
# ---------------------------------------------------------------------------
section "Stage 3.0: Deploy Database Tier"

echo "ENTERPRISE EMPHASIS: The database uses StatefulSet + PVC because data must outlive pod restarts."
apply_manifest "05-database-services.yaml"
apply_manifest "06-database-statefulset.yaml"
run_cmd kubectl rollout status statefulset/patient-record-database -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get pvc -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 4.0: Initialize Database Schema
# Purpose: Create the application table before the backend becomes Ready.
# Expected output: schema Job completes successfully.
# ---------------------------------------------------------------------------
section "Stage 4.0: Initialize Database Schema"

echo "ENTERPRISE EMPHASIS: Schema initialization is a release step. The backend readiness probe also checks that the table exists."
run_cmd kubectl delete job patient-record-schema-initializer -n "${NAMESPACE}" --ignore-not-found=true
apply_manifest "07-database-schema-initialization-job.yaml"
run_cmd kubectl wait --for=condition=complete job/patient-record-schema-initializer -n "${NAMESPACE}" --timeout=180s

# ---------------------------------------------------------------------------
# Stage 5.0: Deploy Backend Tier
# Purpose: Start the stateless FastAPI tier behind a private ClusterIP Service.
# Expected output: Deployment rollout completes and Service endpoints appear.
# ---------------------------------------------------------------------------
section "Stage 5.0: Deploy Backend Tier"

echo "ENTERPRISE EMPHASIS: Readiness gates API traffic until the pod can reach the database."
apply_manifest "08-backend-deployment.yaml"
apply_manifest "09-backend-service.yaml"
run_cmd kubectl rollout status deployment/patient-record-api -n "${NAMESPACE}" --timeout=180s

# ---------------------------------------------------------------------------
# Stage 6.0: Deploy Frontend Tier
# Purpose: Start the UI and expose only this tier to the laptop through NodePort.
# Expected output: UI Deployment rollout completes and NodePort Service exists.
# ---------------------------------------------------------------------------
section "Stage 6.0: Deploy Frontend Tier"

echo "ENTERPRISE EMPHASIS: Only the frontend gets external exposure in this lab. Backend and database stay private."
apply_manifest "10-frontend-deployment.yaml"
apply_manifest "11-frontend-service.yaml"
run_cmd kubectl rollout status deployment/patient-intake-ui -n "${NAMESPACE}" --timeout=180s

# ---------------------------------------------------------------------------
# Stage 7.0: Apply Enterprise Controls
# Purpose: Add traffic policy, disruption protection, autoscaling, ingress, and backup.
# Expected output: NetworkPolicy, PDB, HPA, Ingress, and CronJob objects exist.
# ---------------------------------------------------------------------------
section "Stage 7.0: Apply Enterprise Controls"

apply_manifest "12-network-policy.yaml"
apply_manifest "13-pod-disruption-budgets.yaml"
apply_manifest "14-horizontal-pod-autoscaler.yaml"
apply_manifest "15-frontend-ingress.yaml"
apply_manifest "16-database-backup-cronjob.yaml"

# ---------------------------------------------------------------------------
# Stage 8.0: Show Access and Debug Commands
# Purpose: Leave the learner with the operational entry points.
# Expected output: Services, pods, and browser URL are printed.
# ---------------------------------------------------------------------------
section "Stage 8.0: Show Access and Debug Commands"

run_cmd kubectl get pods -n "${NAMESPACE}" -o wide
run_cmd kubectl get svc -n "${NAMESPACE}"
run_cmd kubectl get endpoints -n "${NAMESPACE}"
run_cmd kubectl get ingress -n "${NAMESPACE}"
run_cmd kubectl get cronjob -n "${NAMESPACE}"

cat <<'TEXT'
What you should see:
  - patient-record-database-0 is Running and Ready.
  - patient-record-api has two Ready pods on a node different from the database pod.
  - patient-intake-ui has two Ready pods.
  - patient-intake-ui-service exposes NodePort 30001.

Open:
  http://localhost:30001

Next verification:
  bash app_k8_deployment/deployment-lifecycle/verify-patient-record-system.sh
TEXT
