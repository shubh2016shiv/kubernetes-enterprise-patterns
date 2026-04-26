#!/usr/bin/env bash
# =============================================================================
# FILE: 03-pods/pod-commands.sh
# PURPOSE: Apply and inspect enterprise-style pod examples.
# =============================================================================

set -e
set -u
set -o pipefail

# CONFIGURATION EXPLANATION The pod examples are created in `applications`, a namespace: a named area inside one
# cluster. Keeping lab workloads here prevents commands from accidentally touching
# Kubernetes system components, and production teams use the same boundary for team
# ownership, permissions, resource budgets, and network rules.
NAMESPACE="applications"
SCRIPTS_DIR="$(dirname "$0")"

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    POD DEPLOYMENT & INSPECTION FLOW                       │
# │                                                                           │
# │  Stage 1: Apply Pod Manifests                                            │
# │      ├── 01-minimal-pod.yaml (Alpine debug container)                    │
# │      ├── 02-pod-with-env.yaml (NGINX with Downward API config)           │
# │      └── 03-multi-container-pod.yaml (app + sidecar helper container)    │
# │                                                                           │
# │  Stage 2: Inspect Pod Status                                             │
# │      ├── List pods in namespace                                          │
# │      └── Describe pod for event history                                  │
# │                                                                           │
# │  Stage 3: Check Container Logs                                           │
# │      ├── Single-container pod logs                                       │
# │      └── Multi-container pod logs (specifying container name)            │
# │                                                                           │
# │  Stage 4: Execute Interactive Commands (Exec)                            │
# │      ├── Check OS inside container                                       │
# │      └── Test internal cluster DNS resolution                            │
# │                                                                           │
# │  Stage 5: Advanced Inspection (JSONPath)                                 │
# │      └── Extract specific fields like Pod IP and Scheduled Node          │
# └──────────────────────────────────────────────────────────────────────────┘

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# A sidecar is a helper container that runs in the same Pod as the main app.
# In this module, the main app writes log lines and the sidecar reads those
# log lines from a shared volume. Both containers share the same Pod lifecycle.

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "\$ $*"
  "$@"
  echo ""
}

section "1. Apply pod manifests"
run_cmd kubectl apply -f "${SCRIPTS_DIR}/01-minimal-pod.yaml"
run_cmd kubectl apply -f "${SCRIPTS_DIR}/02-pod-with-env.yaml"
run_cmd kubectl apply -f "${SCRIPTS_DIR}/03-multi-container-pod.yaml"

# CONFIGURATION EXPLANATION The 60s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
kubectl wait --for=condition=Ready pod/platform-debug-toolbox -n "${NAMESPACE}" --timeout=60s || true
kubectl wait --for=condition=Ready pod/inference-worker-config-demo -n "${NAMESPACE}" --timeout=90s || true
kubectl wait --for=condition=Ready pod/inference-with-log-sidecar -n "${NAMESPACE}" --timeout=120s || true

section "2. List and describe"
run_cmd kubectl get pods -n "${NAMESPACE}"
run_cmd kubectl get pods -n "${NAMESPACE}" -o wide
run_cmd kubectl describe pod platform-debug-toolbox -n "${NAMESPACE}"

section "3. Logs"
# Generate one request so the inference app writes an access log line.
run_cmd kubectl exec inference-with-log-sidecar -n "${NAMESPACE}" -c log-shipper -- \
  wget -qO- http://127.0.0.1:8080/health

run_cmd kubectl logs platform-debug-toolbox -n "${NAMESPACE}" --tail=20
run_cmd kubectl logs inference-worker-config-demo -n "${NAMESPACE}" --tail=20
run_cmd kubectl logs inference-with-log-sidecar -n "${NAMESPACE}" -c inference-app --tail=20
run_cmd kubectl logs inference-with-log-sidecar -n "${NAMESPACE}" -c log-shipper --tail=20

section "4. Exec and runtime checks"
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- uname -a
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- nslookup kubernetes.default.svc.cluster.local
run_cmd kubectl exec inference-worker-config-demo -n "${NAMESPACE}" -- env

section "5. JSONPath quick checks"
run_cmd kubectl get pod platform-debug-toolbox -n "${NAMESPACE}" -o jsonpath='{.status.podIP}'
echo ""
run_cmd kubectl get pod platform-debug-toolbox -n "${NAMESPACE}" -o jsonpath='{.spec.nodeName}'
echo ""
run_cmd kubectl get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

section "6. Useful manual checks"
echo "Run manually:"
echo "  kubectl exec -it platform-debug-toolbox -n ${NAMESPACE} -- /bin/sh"
echo "  kubectl port-forward pod/inference-with-log-sidecar -n ${NAMESPACE} 18080:8080"
echo "  curl -sS http://127.0.0.1:18080/health"

section "7. Cleanup commands"
echo "Delete only these demo pods:"
echo "  kubectl delete pod platform-debug-toolbox inference-worker-config-demo inference-with-log-sidecar -n ${NAMESPACE}"
echo ""
echo "Next step:"
echo "  bash 04-deployments/rolling-update.sh"
