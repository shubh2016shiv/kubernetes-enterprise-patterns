#!/usr/bin/env bash
# =============================================================================
# FILE:    commands.sh
# PURPOSE: Apply and inspect enterprise Kubernetes patterns: NetworkPolicy,
#          PodDisruptionBudget, HorizontalPodAutoscaler, and scheduling controls.
# USAGE:   bash setup/10-enterprise-patterns/commands.sh
# WHEN:    Run after setup/09-health-checks, once the learner understands
#          Deployment health, Service endpoints, and basic debugging.
# PREREQS: Namespace `applications` exists and kubectl points at the kind
#          learning cluster. HPA inspection is best with metrics-server installed.
# OUTPUT:  Gateway/backend workloads exist; enterprise policy objects are applied
#          and inspected with beginner-friendly explanations.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify the applications namespace exists.
#
# Stage 2: Ensure Base Application Exists
#   - Apply gateway/backend Deployments and Services from earlier modules.
#
# Stage 3: Apply Enterprise Policies
#   - Apply NetworkPolicy, PDB, HPA, and scheduling demo manifests.
#
# Stage 4: Inspect Protection State
#   - Inspect the objects and explain what each one protects.
#
# Stage 5: Metrics and Enforcement Notes
#   - Explain local limitations such as metrics-server and CNI enforcement.
#
# Stage 6: Enterprise Debugging Runbook
#   - Leave the learner with production-style checks.
# ---------------------------------------------------------------------------

NAMESPACE="applications"
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
# Purpose: Fail early if namespace prerequisites are missing.
# Expected input: setup/02-namespaces has created applications.
# Expected output: namespace lookup succeeds.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl version --client=true

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "${NAMESPACE} namespace exists"
else
  echo "ERROR: namespace '${NAMESPACE}' does not exist."
  echo "Run: bash setup/02-namespaces/apply-namespaces.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# Stage 2.0: Ensure Base Application Exists
# Purpose: Create the gateway/backend app that enterprise controls protect.
# Expected output: Deployments and Services are created or configured.
# ---------------------------------------------------------------------------
section "Stage 2.0: Ensure Base Application Exists"

run_cmd kubectl apply -f "${SCRIPT_DIR}/../04-deployments/risk-profile-api-deployment.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/../04-deployments/inference-gateway-deployment.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/../05-services/risk-profile-api-clusterip.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/../05-services/clusterip-service.yaml"

run_cmd kubectl rollout status deployment/risk-profile-api-deployment -n "${NAMESPACE}" --timeout=90s
run_cmd kubectl rollout status deployment/inference-gateway-deployment -n "${NAMESPACE}" --timeout=90s

# ---------------------------------------------------------------------------
# Stage 3.0: Apply Enterprise Policies
# Purpose: Add security, availability, autoscaling, and scheduling guardrails.
# Expected output: all enterprise policy objects are created or configured.
# ---------------------------------------------------------------------------
section "Stage 3.0: Apply Enterprise Policies"

run_cmd kubectl apply -f "${SCRIPT_DIR}/network-policy.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/pod-disruption-budget.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/horizontal-pod-autoscaler.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/scheduling-constraints-demo.yaml"
run_cmd kubectl rollout status deployment/scheduling-constraints-demo -n "${NAMESPACE}" --timeout=90s

# ---------------------------------------------------------------------------
# Stage 4.0: Inspect Protection State
# Purpose: Show how each enterprise controller exposes its current state.
# Expected output: NetworkPolicies, PDB, HPA, and scheduling details are visible.
# ---------------------------------------------------------------------------
section "Stage 4.0: Inspect Protection State"

echo "NetworkPolicy objects describe intended pod traffic rules."
run_cmd kubectl get networkpolicy -n "${NAMESPACE}"
run_cmd kubectl describe networkpolicy allow-gateway-to-risk-api -n "${NAMESPACE}"

echo "PDB shows whether voluntary maintenance may evict a gateway pod."
run_cmd kubectl get pdb inference-gateway-pdb -n "${NAMESPACE}"
run_cmd kubectl describe pdb inference-gateway-pdb -n "${NAMESPACE}"

echo "HPA shows desired scaling behavior. TARGETS may be <unknown> without metrics-server."
run_cmd kubectl get hpa inference-gateway-hpa -n "${NAMESPACE}"
run_cmd kubectl describe hpa inference-gateway-hpa -n "${NAMESPACE}"

echo "Scheduling output shows where pods landed."
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=inference-gateway -o wide
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=scheduling-constraints-demo -o wide

# ---------------------------------------------------------------------------
# Stage 5.0: Metrics and Enforcement Notes
# Purpose: Explain local limitations that can confuse beginners.
# Expected output: Clear notes about metrics-server and CNI enforcement.
# ---------------------------------------------------------------------------
section "Stage 5.0: Metrics and Enforcement Notes"

echo "NetworkPolicy note:"
echo "  The YAML is valid, but enforcement depends on the CNI plugin."
echo "  kind's default CNI may not enforce NetworkPolicy. Calico or Cilium would."
echo ""
echo "HPA note:"
echo "  If TARGETS is <unknown>, metrics-server is missing or unhealthy."
echo "  The HPA object can exist before metrics are available."
echo ""
echo "Taint/toleration note:"
echo "  Tolerations matter only when nodes have matching taints."
echo "  This demo does not taint your kind nodes because that can break later labs."

# ---------------------------------------------------------------------------
# Stage 6.0: Enterprise Debugging Runbook
# Purpose: Teach the first checks for each enterprise pattern.
# Expected output: Actionable next steps.
# ---------------------------------------------------------------------------
section "Stage 6.0: Enterprise Debugging Runbook"

echo "1. If traffic is blocked:"
echo "   kubectl get pods -n ${NAMESPACE} --show-labels"
echo "   kubectl describe networkpolicy -n ${NAMESPACE}"
echo ""
echo "2. If node drain is blocked:"
echo "   kubectl describe pdb inference-gateway-pdb -n ${NAMESPACE}"
echo "   kubectl get pods -n ${NAMESPACE} -l app=inference-gateway"
echo ""
echo "3. If HPA does not scale:"
echo "   kubectl get hpa inference-gateway-hpa -n ${NAMESPACE}"
echo "   kubectl top pods -n ${NAMESPACE}"
echo ""
echo "4. If pods do not schedule:"
echo "   kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo "   kubectl get nodes --show-labels"
echo ""
echo "5. If you need to clean up this module:"
echo "   kubectl delete -f ${SCRIPT_DIR}/network-policy.yaml"
echo "   kubectl delete -f ${SCRIPT_DIR}/pod-disruption-budget.yaml"
echo "   kubectl delete -f ${SCRIPT_DIR}/horizontal-pod-autoscaler.yaml"
echo "   kubectl delete -f ${SCRIPT_DIR}/scheduling-constraints-demo.yaml"
echo ""
echo "Fundamentals track complete. Recommended next addition:"
echo "  setup/10-observability-debugging or setup/11-observability-debugging,"
echo "  depending on whether you decide to renumber this enterprise module."
