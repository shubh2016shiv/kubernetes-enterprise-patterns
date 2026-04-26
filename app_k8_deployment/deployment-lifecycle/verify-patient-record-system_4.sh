#!/usr/bin/env bash
# =============================================================================
# FILE:    verify-patient-record-system_4.sh
# PURPOSE: Verify pods, Services, probes, database connectivity, and form submit.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/verify-patient-record-system_4.sh
# WHEN:    Run after deployment or after any rollout/rollback.
# PREREQS: The patient-record-system namespace exists and workloads are running.
# OUTPUT:  Operational evidence that all three tiers are connected correctly.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify namespace exists.
#
# Stage 2: Inspect Workload State
#   - Show pods, Services, endpoints, Ingress, PDB, HPA, and backups.
#
# Stage 3: Check Backend Through Frontend Path
#   - Use localhost NodePort to call metadata and readiness.
#
# Stage 4: Submit Patient Record
#   - POST a realistic patient payload through the same path as the UI.
#
# Stage 5: Troubleshooting Pointers
#   - Print next checks if the workflow fails.
# ---------------------------------------------------------------------------

# CAN BE CHANGED: Namespace name. Must match NAMESPACE in deploy-patient-record-system_3.sh
# and the namespace value in all YAML files. Example: `patient-intake-system`.
# CONFIGURATION EXPLANATION This namespace value tells every verification command where to look. A namespace is
# a named boundary inside one cluster; if this does not match the manifests, the script may report missing pods
# even though the app is running somewhere else.
NAMESPACE="patient-record-system"
# CAN BE CHANGED: Base URL for health checks and form submission tests.
# If the NodePort or host port changes in kind-cluster-config.yaml, update this.
# Example: http://localhost:8080 (if you remap port 30001 to 8080).
# Override via environment: BASE_URL=http://localhost:8080 bash verify-patient-record-system_4.sh
# CONFIGURATION EXPLANATION `http://localhost:30001` is the learner-facing URL created by the NodePort Service.
# NodePort is a local exposure shortcut; enterprise systems usually verify through a real DNS name, TLS, and a
# load balancer or ingress gateway.
BASE_URL="${BASE_URL:-http://localhost:30001}"

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
# Purpose: Fail early if the namespace or curl is missing.
# Expected input: Deployment script has completed.
# Expected output: namespace lookup succeeds and curl exists.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl get namespace "${NAMESPACE}"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required for this verification script."
  echo "Install curl inside WSL2 or use the manual kubectl checks printed below."
  exit 1
fi

# ---------------------------------------------------------------------------
# Stage 2.0: Inspect Workload State
# Purpose: Show the Kubernetes control-plane view of all three tiers.
# Expected output: pods are Ready; Services have endpoints.
# ---------------------------------------------------------------------------
section "Stage 2.0: Inspect Workload State"

run_cmd kubectl get pods -n "${NAMESPACE}" -o wide
run_cmd kubectl get svc -n "${NAMESPACE}"
run_cmd kubectl get endpoints -n "${NAMESPACE}"
run_cmd kubectl get ingress -n "${NAMESPACE}"
run_cmd kubectl get pdb -n "${NAMESPACE}"
run_cmd kubectl get hpa -n "${NAMESPACE}"
run_cmd kubectl get cronjob -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 3.0: Check Backend Through Frontend Path
# Purpose: Verify nginx -> backend Service -> API works.
# Expected input: NodePort 30001 is mapped by the kind cluster config.
# Expected output: JSON metadata and readiness responses.
# ---------------------------------------------------------------------------
section "Stage 3.0: Check Backend Through Frontend Path"

echo "ENTERPRISE EMPHASIS: This verifies the user-facing path, not just an isolated pod check."
run_cmd curl --fail --silent --show-error "${BASE_URL}/api/"
run_cmd curl --fail --silent --show-error "${BASE_URL}/api/readyz"

# ---------------------------------------------------------------------------
# Stage 4.0: Submit Patient Record
# Purpose: Prove the UI path can write through FastAPI into SQL.
# Expected output: HTTP 201 JSON response containing patient_id and pod identity.
# ---------------------------------------------------------------------------
section "Stage 4.0: Submit Patient Record"

run_cmd curl --fail --silent --show-error \
  --request POST \
  --header "Content-Type: application/json" \
  --data '{
    "full_name": "Asha Mehta",
    "date_of_birth": "1991-08-14",
    "gender": "female",
    "phone_number": "+1-555-0100",
    "email_address": "asha.mehta@example.com",
    "primary_symptom": "Persistent fever and fatigue",
    "triage_priority": "urgent"
  }' \
  "${BASE_URL}/api/patients"

# ---------------------------------------------------------------------------
# Stage 5.0: Troubleshooting Pointers
# Purpose: Give production-style next checks if any earlier command fails.
# Expected output: Clear commands to continue debugging.
# ---------------------------------------------------------------------------
section "Stage 5.0: Troubleshooting Pointers"

cat <<TEXT
If verification fails, check:
  kubectl describe pod -n ${NAMESPACE} -l app=patient-record-api
  kubectl logs -n ${NAMESPACE} deployment/patient-record-api
  kubectl describe svc patient-intake-ui-service -n ${NAMESPACE}
  kubectl describe networkpolicy -n ${NAMESPACE}
  kubectl logs -n ${NAMESPACE} job/patient-record-schema-initializer
  kubectl top pods -n ${NAMESPACE}
  kubectl get events -n ${NAMESPACE} --sort-by=.lastTimestamp

Open in browser:
  ${BASE_URL}
TEXT
