#!/usr/bin/env bash
# =============================================================================
# FILE:    observe-lifecycle.sh
# PURPOSE: Show exactly what happens to pods when a Deployment restarts,
#          rolls, reschedules, and scales.
# USAGE:   bash setup/04-deployments/observe-lifecycle.sh
# WHEN:    Run after rolling-update.sh, before moving to setup/05-services.
# PREREQS: Namespace `applications` exists, kubectl points at the learning
#          cluster, and the gateway/backend Deployments can be applied.
# OUTPUT:  A step-by-step operator view of Deployment reconciliation:
#          pod replacement, ReplicaSet ownership, node rescheduling, and scaling.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# SCRIPT FLOW
#
#   Stage 1: Prepare and Baseline
#       -> Ensure both Deployments exist and print current pods/nodes.
#
#   Stage 2: Pod Restart / Replacement
#       -> Delete one gateway pod and watch the ReplicaSet create a replacement.
#
#   Stage 3: Rolling Restart
#       -> Ask Kubernetes to restart all gateway pods safely through Deployment.
#
#   Stage 4: Reschedule Drill
#       -> Cordon a node, delete one backend pod from that node, watch replacement
#          land on another schedulable node, then uncordon the original node.
#
#   Stage 5: Scale Drill
#       -> Scale gateway up and down and watch desired state reconciliation.
#
#   Stage 6: Final Operator Checklist
#       -> Print the exact production commands to remember.
# -----------------------------------------------------------------------------

# CONFIGURATION EXPLANATION `applications` is the namespace that holds the two Deployments in this module. A
# namespace is not a separate cluster; it is a boundary inside the cluster where
# Kubernetes can apply permissions, quotas, and cleanup commands to one application
# area.
NAMESPACE="applications"
# CONFIGURATION EXPLANATION `inference-gateway-deployment` is the Deployment name that kubectl will update, roll
# back, or inspect. Keeping this explicit prevents the script from changing the
# sibling Deployment when the lesson is about isolating rollout blast radius.
GATEWAY_DEPLOYMENT="inference-gateway-deployment"
# CONFIGURATION EXPLANATION `risk-profile-api-deployment` is the Deployment name that kubectl will update, roll
# back, or inspect. Keeping this explicit prevents the script from changing the
# sibling Deployment when the lesson is about isolating rollout blast radius.
BACKEND_DEPLOYMENT="risk-profile-api-deployment"
MANIFESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# CONFIGURATION EXPLANATION This starts empty and is filled only if the demo marks a node unschedulable.
# Tracking it lets the cleanup step restore the node, which models the production
# habit of undoing temporary failure-drill changes.
NODE_TO_UNCORDON=""

cleanup() {
  if [ -n "${NODE_TO_UNCORDON}" ]; then
    echo ""
    echo "Cleanup: ensuring node ${NODE_TO_UNCORDON} is schedulable again."
    kubectl uncordon "${NODE_TO_UNCORDON}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "\$ $*"
  "$@"
  echo ""
}

first_gateway_pod() {
  kubectl get pod -n "${NAMESPACE}" \
    -l app=inference-gateway \
    -o jsonpath='{.items[0].metadata.name}'
}

first_backend_pod() {
  kubectl get pod -n "${NAMESPACE}" \
    -l app=risk-profile-api \
    -o jsonpath='{.items[0].metadata.name}'
}

pod_node_name() {
  local pod_name="$1"
  kubectl get pod "${pod_name}" -n "${NAMESPACE}" -o jsonpath='{.spec.nodeName}'
}

# -----------------------------------------------------------------------------
# Stage 1.0: Prepare and Baseline
# Purpose: Make sure the desired state exists before disturbing anything.
# Expected input: working cluster and applications namespace.
# Expected output: both Deployments are available and pod placement is visible.
# -----------------------------------------------------------------------------
section "Stage 1.0: Prepare and Baseline"

echo "Applying both Deployments so this drill starts from a known desired state."
run_cmd kubectl apply -f "${MANIFESTS_DIR}/risk-profile-api-deployment.yaml" -n "${NAMESPACE}"
run_cmd kubectl apply -f "${MANIFESTS_DIR}/inference-gateway-deployment.yaml" -n "${NAMESPACE}"

# CONFIGURATION EXPLANATION The 180s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
run_cmd kubectl rollout status deployment/"${BACKEND_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s

echo "Baseline: Deployments are the desired-state controllers."
run_cmd kubectl get deployments -n "${NAMESPACE}"

echo "Baseline: Pods are the actual running workload instances."
run_cmd kubectl get pods -n "${NAMESPACE}" -l tier=backend -o wide

echo "Baseline: Nodes are where the scheduler placed those pods."
run_cmd kubectl get nodes -o wide

# -----------------------------------------------------------------------------
# Stage 2.0: Pod Restart / Replacement
# Purpose: Prove that deleting a pod is not deleting the application.
# Expected output: the old pod disappears and a new pod with a different name appears.
# -----------------------------------------------------------------------------
section "Stage 2.0: Pod Restart / Replacement"

POD_TO_DELETE="$(first_gateway_pod)"
NODE_BEFORE_DELETE="$(pod_node_name "${POD_TO_DELETE}")"

echo "Deleting one gateway pod: ${POD_TO_DELETE}"
echo "It currently runs on node: ${NODE_BEFORE_DELETE}"
echo ""
echo "Production meaning:"
echo "  This is similar to a pod crash or manual pod deletion during debugging."
echo "  The ReplicaSet should notice actual replicas dropped below desired replicas"
echo "  and create a replacement pod."
echo ""

run_cmd kubectl delete pod "${POD_TO_DELETE}" -n "${NAMESPACE}"
# CONFIGURATION EXPLANATION The 180s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=inference-gateway -o wide

# -----------------------------------------------------------------------------
# Stage 3.0: Rolling Restart
# Purpose: Show the safe Deployment-level way to restart all pods.
# Expected output: Kubernetes replaces pods gradually and waits for readiness.
# -----------------------------------------------------------------------------
section "Stage 3.0: Rolling Restart"

echo "A rolling restart changes the pod template annotation."
echo "That causes the Deployment to create a new ReplicaSet revision without changing the image."
echo ""

run_cmd kubectl rollout restart deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}"
# CONFIGURATION EXPLANATION The 180s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get replicasets -n "${NAMESPACE}" -l app=inference-gateway
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=inference-gateway -o wide

# -----------------------------------------------------------------------------
# Stage 4.0: Reschedule Drill
# Purpose: Show scheduling behavior when one node is made unavailable for new pods.
# Expected output: replacement pod lands on a different schedulable node when possible.
# -----------------------------------------------------------------------------
section "Stage 4.0: Reschedule Drill"

SCHEDULABLE_NODE_COUNT="$(kubectl get nodes --no-headers | awk '$2 == "Ready" { count++ } END { print count+0 }')"

if [ "${SCHEDULABLE_NODE_COUNT}" -lt 2 ]; then
  echo "Skipping reschedule drill because fewer than two Ready nodes are available."
  echo "Production meaning:"
  echo "  Rescheduling needs another node where the replacement pod can land."
else
  POD_TO_RESCHEDULE="$(first_backend_pod)"
  NODE_TO_CORDON="$(pod_node_name "${POD_TO_RESCHEDULE}")"
  # CONFIGURATION EXPLANATION This starts empty and is filled only if the demo marks a node unschedulable.
  # Tracking it lets the cleanup step restore the node, which models the production
  # habit of undoing temporary failure-drill changes.
  NODE_TO_UNCORDON="${NODE_TO_CORDON}"

  echo "Selected pod: ${POD_TO_RESCHEDULE}"
  echo "Selected node to cordon: ${NODE_TO_CORDON}"
  echo ""
  echo "Cordon means: do not schedule NEW pods here."
  echo "It does not kill existing pods by itself."
  echo "This drill uses the backend Deployment because it has a softer spread rule,"
  echo "which makes it better for a local rescheduling demonstration."
  echo ""

  run_cmd kubectl cordon "${NODE_TO_CORDON}"
  run_cmd kubectl delete pod "${POD_TO_RESCHEDULE}" -n "${NAMESPACE}"
  # CONFIGURATION EXPLANATION The 180s timeout is a guardrail for automation: if Kubernetes cannot finish the
  # rollout or readiness wait by then, the learner gets a clear failure instead of an
  # endless terminal. Production CI/CD pipelines use the same pattern to protect
  # runner capacity and surface broken releases quickly.
  run_cmd kubectl rollout status deployment/"${BACKEND_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
  run_cmd kubectl get pods -n "${NAMESPACE}" -l app=risk-profile-api -o wide

  echo "Uncordoning the node so the lab cluster returns to normal."
  run_cmd kubectl uncordon "${NODE_TO_CORDON}"
  # CONFIGURATION EXPLANATION This starts empty and is filled only if the demo marks a node unschedulable.
  # Tracking it lets the cleanup step restore the node, which models the production
  # habit of undoing temporary failure-drill changes.
  NODE_TO_UNCORDON=""
fi

# -----------------------------------------------------------------------------
# Stage 5.0: Scale Drill
# Purpose: Show that scaling changes desired replicas and ReplicaSet reconciles.
# Expected output: pod count grows to 5, then returns to 3.
# -----------------------------------------------------------------------------
section "Stage 5.0: Scale Drill"

run_cmd kubectl scale deployment/"${GATEWAY_DEPLOYMENT}" --replicas=5 -n "${NAMESPACE}"
# CONFIGURATION EXPLANATION The 180s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get deployment "${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}"
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=inference-gateway -o wide

run_cmd kubectl scale deployment/"${GATEWAY_DEPLOYMENT}" --replicas=3 -n "${NAMESPACE}"
# CONFIGURATION EXPLANATION The 180s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get deployment "${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}"

# -----------------------------------------------------------------------------
# Stage 6.0: Final Operator Checklist
# Purpose: Leave the learner with production-grade observation commands.
# Expected output: a compact mental model and commands to practice.
# -----------------------------------------------------------------------------
section "Stage 6.0: Final Operator Checklist"

echo "When pods restart, roll, reschedule, or scale, inspect in this order:"
echo ""
echo "1. Desired state:"
echo "   kubectl get deployment ${GATEWAY_DEPLOYMENT} -n ${NAMESPACE}"
echo ""
echo "2. Revision ownership:"
echo "   kubectl get rs -n ${NAMESPACE} -l app=inference-gateway"
echo ""
echo "3. Actual pods and node placement:"
echo "   kubectl get pods -n ${NAMESPACE} -l app=inference-gateway -o wide"
echo ""
echo "4. Why a pod is not healthy or scheduled:"
echo "   kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo ""
echo "5. Rollout progress:"
echo "   kubectl rollout status deployment/${GATEWAY_DEPLOYMENT} -n ${NAMESPACE}"
echo ""
echo "Enterprise translation:"
echo "  In EKS/GKE/AKS, the commands are the same. The difference is that node loss,"
echo "  autoscaling, alerts, admission policies, and GitOps controllers add more context."
