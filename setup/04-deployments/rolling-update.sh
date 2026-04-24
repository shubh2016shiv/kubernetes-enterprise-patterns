#!/usr/bin/env bash
# =============================================================================
# FILE: 04-deployments/rolling-update.sh
# PURPOSE: Demonstrates zero-downtime rolling updates and rollback.
#          THE single most important operational pattern in Kubernetes.
#
# WHAT YOU'LL LEARN:
#   1. How to deploy an application with kubectl apply
#   2. How to watch a rolling update happen in real-time
#   3. How Kubernetes ensures zero downtime during updates
#   4. How rollout history works (audit trail)
#   5. How to rollback to a previous version instantly
#
# ENTERPRISE CONTEXT:
#   In real enterprise, this is done via CI/CD:
#     - GitHub Actions updates the image tag in deployment YAML
#     - ArgoCD/Flux detects the change and applies it to the cluster
#     - K8s performs the rolling update automatically
#   The kubectl commands here are what happen UNDER THE HOOD in that pipeline.
# =============================================================================

set -e
set -u
set -o pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    ROLLING UPDATE FLOW                                    │
# │                                                                           │
# │  Stage 1: Deploy Initial Version                                         │
# │      └── Apply nginx-deployment.yaml (v1.25.4)                           │
# │                                                                           │
# │  Stage 2: Perform Rolling Update                                         │
# │      └── kubectl set image to v1.26.2                                    │
# │                                                                           │
# │  Stage 3: Check Rollout History                                          │
# │      └── kubectl rollout history deployment                              │
# │                                                                           │
# │  Stage 4: Emergency Rollback                                             │
# │      └── kubectl rollout undo deployment                                 │
# │                                                                           │
# │  Stage 5: Manual Scaling Operations                                      │
# │      └── kubectl scale deployment                                        │
# └──────────────────────────────────────────────────────────────────────────┘

NAMESPACE="applications"
DEPLOYMENT="nginx-deployment"
MANIFESTS_DIR="$(dirname "$0")"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

section() {
  echo ""
  echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}${BOLD}  $1${RESET}"
  echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
  echo ""
}

run_cmd() {
  echo -e "  ${BOLD}\$ $*${RESET}"
  eval "$@"
  echo ""
}

info() {
  echo -e "  ${YELLOW}▸${RESET} $1"
}

# =============================================================================
# STEP 1: DEPLOY INITIAL VERSION (nginx 1.25.4)
# =============================================================================
section "Step 1: Deploy Initial Version (nginx:1.25.4)"

info "Applying the deployment manifest..."
run_cmd kubectl apply -f "${MANIFESTS_DIR}/nginx-deployment.yaml" -n "${NAMESPACE}"

info "Waiting for all 3 replicas to be ready..."
# --for=condition=Available: waits until AVAILABLE replicas == desired replicas
# This is different from just pods being created — they must pass readiness probes
run_cmd kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=120s

info "Current deployment state:"
# READY: X/Y where X=running, Y=desired
# UP-TO-DATE: pods running the latest spec
# AVAILABLE: pods ready to serve traffic (passed readiness probe)
run_cmd kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}"

info "Pods created by this deployment:"
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=nginx -o wide

# =============================================================================
# STEP 2: PERFORM A ROLLING UPDATE
# =============================================================================
section "Step 2: Rolling Update to nginx:1.26.2"

info "BEFORE the update, open a second terminal and run:"
info "  watch kubectl get pods -n ${NAMESPACE} -l app=nginx"
info "This shows you pods being replaced in real-time."
info ""
info "The rolling update process:"
info "  1. K8s creates 1 NEW pod with nginx:1.26.2 (maxSurge=1)"
info "  2. New pod passes readiness probe"
info "  3. K8s terminates 1 OLD pod with nginx:1.25.4 (maxUnavailable=1)"
info "  4. Repeat until all old pods are replaced"
info "  At all times: at least 2 pods are serving traffic (replicas - maxUnavailable)"
echo ""

# METHOD 1: Update image via kubectl set image
# ENTERPRISE EQUIVALENT: CI/CD pipeline updates the image tag in YAML → kubectl apply
# In GitOps: Argo CD / Flux detects the tag change in Git and applies it
#
# kubectl set image <deployment>/<container>=<image>:<tag>
# Record the change cause for rollout history (good practice in enterprise)
run_cmd kubectl set image deployment/"${DEPLOYMENT}" \
  nginx=nginx:1.26.2 \
  --namespace="${NAMESPACE}"

info "Watching the rolling update (Ctrl+C when done)..."
info "STATUS column transitions: Pending → ContainerCreating → Running"
info ""

# kubectl rollout status blocks until the rollout completes (or times out)
# Exit code 0 = success, non-zero = failure/timeout
# In CI/CD: if this returns non-zero, the pipeline fails and triggers rollback
run_cmd kubectl rollout status deployment/"${DEPLOYMENT}" \
  --namespace="${NAMESPACE}" \
  --timeout=120s

info "Update complete! All pods now run nginx:1.26.2"
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=nginx -o wide

# Verify the new image version
info "Verify image version on one of the pods:"
POD_NAME=$(kubectl get pod -n "${NAMESPACE}" -l app=nginx -o jsonpath='{.items[0].metadata.name}')
run_cmd kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.containers[0].image}'
echo ""

# =============================================================================
# STEP 3: ROLLOUT HISTORY
# =============================================================================
section "Step 3: Rollout History — Your Audit Trail"

info "View the deployment revision history:"
# Every `kubectl set image` or `kubectl apply` with a changed spec creates a new revision
# In enterprise: each revision corresponds to a CI/CD pipeline run / Git commit
run_cmd kubectl rollout history deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"

info "View details of a specific revision (what changed):"
# Revision 1 = initial deployment, Revision 2 = our update
run_cmd kubectl rollout history deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --revision=1

run_cmd kubectl rollout history deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --revision=2

info "Behind the scenes: K8s keeps old ReplicaSets for rollback:"
# You can see old (0 desired) ReplicaSets that K8s preserves for rollback
# The number of old ReplicaSets kept is controlled by .spec.revisionHistoryLimit
# Default is 10 — in enterprise, reduce to 3-5 to save etcd storage
run_cmd kubectl get replicasets -n "${NAMESPACE}" -l app=nginx

# =============================================================================
# STEP 4: ROLLBACK
# =============================================================================
section "Step 4: Rollback — Undo to Previous Version"

info "Simulating: We discovered nginx:1.26.2 has a critical bug."
info "Rolling back to previous version instantly..."
info ""

# METHOD 1: Undo to PREVIOUS revision
# This is the emergency rollback command every K8s engineer must know
# It literally reverses the last deployment by reactivating the previous ReplicaSet
run_cmd kubectl rollout undo deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"

# Wait for rollback to complete
run_cmd kubectl rollout status deployment/"${DEPLOYMENT}" \
  --namespace="${NAMESPACE}" \
  --timeout=120s

info "Rollback complete! Verify the image version reverted:"
POD_NAME=$(kubectl get pod -n "${NAMESPACE}" -l app=nginx -o jsonpath='{.items[0].metadata.name}')
run_cmd kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.containers[0].image}'
echo ""

info "METHOD 2: Roll back to a SPECIFIC revision:"
info "kubectl rollout undo deployment/${DEPLOYMENT} --to-revision=1 -n ${NAMESPACE}"
echo ""

info "ENTERPRISE ROLLBACK WORKFLOW:"
info "  1. Incident detected (alerting: CPU spike, error rate > threshold)"
info "  2. SRE runs: kubectl rollout undo deployment/<name> -n <ns>"
info "  3. K8s reactivates old ReplicaSet (pods switch instantly)"
info "  4. Mean Time To Recovery (MTTR) in seconds, not minutes"
info "  5. Post-incident: fix the code, redeploy properly via CI/CD"

# =============================================================================
# STEP 5: SCALING
# =============================================================================
section "Step 5: Manual Scaling"

info "Scale UP to 5 replicas (traffic spike response):"
# In enterprise: done via Horizontal Pod Autoscaler (Phase 10) automatically
# Manual scaling is for emergency capacity increases
run_cmd kubectl scale deployment/"${DEPLOYMENT}" --replicas=5 -n "${NAMESPACE}"

info "Watch the new pods appear:"
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=nginx

info "Scale DOWN to 2 replicas (off-hours, cost savings):"
run_cmd kubectl scale deployment/"${DEPLOYMENT}" --replicas=2 -n "${NAMESPACE}"

info "Back to 3 replicas for normal operation:"
run_cmd kubectl scale deployment/"${DEPLOYMENT}" --replicas=3 -n "${NAMESPACE}"

# Wait for scale back
run_cmd kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=60s

# =============================================================================
# FINAL STATE
# =============================================================================
section "Final State"

run_cmd kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}"
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=nginx -o wide

echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  ✓ Rolling Update Demo Complete${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Key commands learned:${RESET}"
echo -e "  kubectl rollout status deployment/<name>         Watch rollout progress"
echo -e "  kubectl rollout history deployment/<name>        Revision history"
echo -e "  kubectl rollout undo deployment/<name>           Roll back to previous"
echo -e "  kubectl rollout undo deployment/<name> --to-revision=N  Specific version"
echo -e "  kubectl scale deployment/<name> --replicas=N    Scale manually"
echo -e "  kubectl set image deployment/<name> <c>=<img>   Update image"
echo ""
echo -e "  ${BOLD}Next step:${RESET} bash 05-services/service-commands.sh"
echo ""
