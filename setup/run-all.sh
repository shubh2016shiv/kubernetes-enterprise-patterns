#!/usr/bin/env bash
# =============================================================================
# FILE: setup/run-all.sh
# PURPOSE: The master curriculum runner. Walk through every phase of the
#          enterprise Kubernetes setup in a controlled, educational sequence.
#
# This is NOT meant to be run in one shot blindly.
# Each phase PAUSES and asks you to confirm before proceeding.
# Read every output. Understand what happened before pressing Enter.
#
# HOW TO RUN:
#   bash run-all.sh
#   (from the setup/ directory inside WSL2, Linux, macOS, or Git Bash)
#
# INTERACTIVE MODE:
#   The script will pause at each phase and explain what to observe.
#   This is intentional — take time to explore before moving on.
# =============================================================================

set -e
set -u
set -o pipefail

SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="applications"

# ─── COLORS ───────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── HELPER: pause and explain ─────────────────────────────────────────────────
# Every phase ends with this function.
# Forces the learner to READ the output before blindly running the next step.
pause_and_reflect() {
  local message="$1"
  echo ""
  echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════════════${RESET}"
  echo -e "${YELLOW}${BOLD}  PAUSE AND REFLECT${RESET}"
  echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════════════${RESET}"
  echo -e "  ${message}"
  echo ""
  read -r -p "  Press ENTER when ready to continue (Ctrl+C to stop)..."
}

# ─── HEADER ───────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║     ENTERPRISE KUBERNETES — COMPLETE LEARNING CURRICULUM             ║
║                                                                      ║
║     From Zero to Production-Grade K8s Engineer                       ║
║                                                                      ║
║     Phases:                                                          ║
║       0 → Prerequisites Check                                        ║
║       1 → Cluster Creation (3-node enterprise topology)              ║
║       2 → Namespace Setup (isolation, RBAC boundaries)               ║
║       3 → Pods (atomic units, sidecars, init containers)             ║
║       4 → Deployments (self-healing, rolling updates, rollback)      ║
║       5 → Services (ClusterIP, NodePort, DNS, Endpoints)             ║
║       6 → ConfigMaps & Secrets (externalized config)                 ║
║       7 → RBAC (identity, roles, bindings)                           ║
║       8 → Resource Management (quotas, limits, QoS)                  ║
║       9 → Health Checks (startup, liveness, readiness probes)        ║
║      10 → Enterprise Patterns (NetworkPolicy, PDB)                   ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"

echo -e "  ${BOLD}Environment:${RESET} Bash (WSL2 / Git Bash / Linux / macOS)"
echo -e "  ${BOLD}Shell:${RESET}       $(bash --version | head -1)"
echo -e "  ${BOLD}Time:${RESET}        $(date)"
echo ""

pause_and_reflect "This curriculum walks through a COMPLETE enterprise Kubernetes setup.
  Each phase builds on the previous. Take time to read each output.
  All the learning is in the COMMENTS of the YAML and script files."

# =============================================================================
# PHASE 0: PREREQUISITES
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 0: Prerequisites Check                            ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
bash "${SETUP_DIR}/00-prerequisites/check-prerequisites.sh"

pause_and_reflect "Did all checks pass?
  If Docker is not running: Open Docker Desktop on Windows first.
  If kind is missing: See 00-prerequisites/install-guide.md
  If kubectl is missing: See 00-prerequisites/install-guide.md"

# =============================================================================
# PHASE 1: CLUSTER SETUP
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 1: Creating Enterprise Cluster                    ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Reading: ${BOLD}01-cluster-setup/kind-cluster-config.yaml${RESET}"
echo -e "  → This YAML defines: 1 control-plane + 2 workers"
echo -e "  → Pinned to Kubernetes v1.30.6 (enterprise version stability)"
echo -e "  → Port-mapped for NodePort access from localhost"
echo ""
bash "${SETUP_DIR}/01-cluster-setup/create-cluster.sh"

echo ""
echo -e "${BOLD}Running post-create health verification...${RESET}"
bash "${SETUP_DIR}/01-cluster-setup/verify-cluster.sh"

pause_and_reflect "EXPLORE BEFORE CONTINUING:
  kubectl get nodes -o wide              → See 3 nodes (1 control, 2 workers)
  kubectl get pods -A                    → See ALL system pods
  kubectl get namespaces                 → See built-in namespaces
  kubectl cluster-info                   → API server address
  kubectl api-resources                  → ALL resource types in this K8s version
  docker ps | grep kind                  → See kind nodes as Docker containers"

# =============================================================================
# PHASE 2: NAMESPACES
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 2: Enterprise Namespace Structure                 ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
bash "${SETUP_DIR}/02-namespaces/apply-namespaces.sh"

pause_and_reflect "EXPLORE:
  kubectl get namespaces --show-labels   → See our custom namespaces with labels
  kubectl describe namespace applications → Full namespace details + annotations
  kubectl get namespaces -o yaml         → Raw YAML (what's actually stored in etcd)"

# =============================================================================
# PHASE 3: PODS
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 3: Pods — The Atomic Unit                         ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Before running: Open 03-pods/01-minimal-pod.yaml in your editor."
echo -e "  Read EVERY COMMENT. Each field is a lesson."
echo ""
bash "${SETUP_DIR}/03-pods/pod-commands.sh"

pause_and_reflect "EXPLORE:
  kubectl get pods -n applications -o wide         → Pod IPs and node placement
  kubectl describe pod platform-debug-toolbox -n applications → Full pod details
  kubectl exec -it platform-debug-toolbox -n applications -- /bin/sh
    → You are now INSIDE the container!
    → Try: cat /etc/resolv.conf   (CoreDNS config)
    → Try: exit
  kubectl exec inference-worker-config-demo -n applications -- env | grep POD_
    → See Downward API vars from the env-demo pod
  kubectl logs inference-with-log-sidecar -n applications -c log-shipper
    → See sidecar container logs"

# =============================================================================
# PHASE 4: DEPLOYMENTS
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 4: Deployments — Self-Healing + Rolling Updates   ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Before running: Open 04-deployments/nginx-deployment.yaml"
echo -e "  Read the spec.strategy section (rolling update config)"
echo -e "  Read the topologySpreadConstraints (HA pod distribution)"
echo ""
bash "${SETUP_DIR}/04-deployments/rolling-update.sh"

pause_and_reflect "EXPLORE:
  kubectl get deployments -n applications          → Deployment status
  kubectl get replicasets -n applications          → See revision history as RSets
  kubectl rollout history deployment/nginx-deployment -n applications
  kubectl get pods -n applications -l app=nginx -o wide  → Which node each pod is on
  
  SELF-HEALING DEMO:
    kubectl delete pod <any-nginx-pod> -n applications
    kubectl get pods -n applications -w    (watch ReplicaSet recreate it instantly)"

# =============================================================================
# PHASE 5: SERVICES
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 5: Services — Stable Endpoints + DNS              ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
bash "${SETUP_DIR}/05-services/service-commands.sh"

pause_and_reflect "EXPLORE:
  kubectl get services -n applications             → See ClusterIP and NodePort
  kubectl get endpoints -n applications            → See pod IPs behind each service
  
  BROWSER TEST: Open http://localhost:30000
    → nginx welcome page served from inside your K8s cluster!
  
  DNS TEST (from inside cluster):
    kubectl exec -it platform-debug-toolbox -n applications -- nslookup nginx-clusterip
    → CoreDNS resolves to the Service's ClusterIP"

# =============================================================================
# PHASE 6: CONFIGMAPS & SECRETS
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 6: ConfigMaps & Secrets                           ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
kubectl apply -f "${SETUP_DIR}/06-configmaps-secrets/app-configmap.yaml"
kubectl apply -f "${SETUP_DIR}/06-configmaps-secrets/app-secret.yaml"
kubectl apply -f "${SETUP_DIR}/06-configmaps-secrets/pod-using-config.yaml"

# Wait for the pod to be ready
kubectl wait --for=condition=Ready pod/nginx-full-config-demo \
  -n "${NAMESPACE}" --timeout=60s || true

echo ""
echo -e "${GREEN}✓ ConfigMap, Secret, and demo pod applied!${RESET}"

pause_and_reflect "EXPLORE:
  kubectl get configmap nginx-app-config -n applications -o yaml
    → See config file stored as YAML value (nginx.conf key)
  
  kubectl get secret nginx-app-secrets -n applications -o yaml
    → See base64-encoded values
  
  kubectl get secret nginx-app-secrets -n applications \
    -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
    → Decode a secret value
  
  kubectl exec nginx-full-config-demo -n applications -- env | grep -E 'APP_|LOG_|DB_'
    → See ConfigMap and Secret values injected as env vars
  
  kubectl exec nginx-full-config-demo -n applications -- ls /etc/app/secrets/
    → See Secret values mounted as files"

# =============================================================================
# PHASE 7: RBAC
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 7: RBAC — Identity and Access Control             ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
kubectl apply -f "${SETUP_DIR}/07-rbac/service-account.yaml"
kubectl apply -f "${SETUP_DIR}/07-rbac/role.yaml"
kubectl apply -f "${SETUP_DIR}/07-rbac/rolebinding.yaml"
kubectl apply -f "${SETUP_DIR}/07-rbac/clusterrole.yaml"

echo ""
echo -e "${GREEN}✓ ServiceAccounts, Roles, and RoleBindings applied!${RESET}"

pause_and_reflect "EXPLORE:
  kubectl get serviceaccounts -n applications
  kubectl get roles -n applications
  kubectl get rolebindings -n applications
  
  TEST PERMISSIONS:
    kubectl auth can-i list pods -n applications \
      --as=system:serviceaccount:applications:nginx-service-account
    → yes  (allowed by nginx-pod-reader role)
    
    kubectl auth can-i delete secrets -n applications \
      --as=system:serviceaccount:applications:nginx-service-account
    → no   (not in the role)
    
    kubectl auth can-i '*' '*' -n applications
    → yes  (you have cluster-admin, check as admin)"

# =============================================================================
# PHASE 8: RESOURCE MANAGEMENT
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 8: Resource Quotas and Limit Ranges               ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
kubectl apply -f "${SETUP_DIR}/08-resource-management/resource-quota.yaml"
kubectl apply -f "${SETUP_DIR}/08-resource-management/limit-range.yaml"
kubectl apply -f "${SETUP_DIR}/08-resource-management/deployment-with-limits.yaml"

echo ""
echo -e "${GREEN}✓ ResourceQuota and LimitRange applied!${RESET}"

pause_and_reflect "EXPLORE:
  kubectl describe resourcequota applications-quota -n applications
    → See USED vs HARD limits for CPU, memory, pods, services
  
  kubectl describe limitrange applications-limit-range -n applications
    → See default, min, and max per container"

# =============================================================================
# PHASE 9: HEALTH CHECKS
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 9: Health Probes                                  ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
kubectl apply -f "${SETUP_DIR}/09-health-checks/health-checks-demo.yaml"
kubectl rollout status deployment/probes-demo -n "${NAMESPACE}" --timeout=120s

echo ""
echo -e "${GREEN}✓ Health check demo deployed!${RESET}"

pause_and_reflect "EXPLORE:
  kubectl describe pod -n applications -l app=probes-demo
    → See all three probes configured
    → Look at 'Conditions:' and 'Events:'
  
  SIMULATE LIVENESS FAILURE:
    PODNAME=\$(kubectl get pods -n applications -l app=probes-demo -o jsonpath='{.items[0].metadata.name}')
    kubectl exec \$PODNAME -n applications -- nginx -s stop
    kubectl get pod \$PODNAME -n applications -w
    → Watch RESTARTS increment as K8s restarts the container"

# =============================================================================
# PHASE 10: ENTERPRISE PATTERNS
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  PHASE 10: Enterprise Patterns                           ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
kubectl apply -f "${SETUP_DIR}/10-enterprise-patterns/network-policy.yaml"
kubectl apply -f "${SETUP_DIR}/10-enterprise-patterns/pod-disruption-budget.yaml"
kubectl apply -f "${SETUP_DIR}/10-enterprise-patterns/horizontal-pod-autoscaler.yaml"

echo ""
echo -e "${GREEN}✓ NetworkPolicy, PodDisruptionBudget, and HPA applied!${RESET}"

pause_and_reflect "EXPLORE:
  kubectl get networkpolicies -n applications
  kubectl describe networkpolicy default-deny-all -n applications
  
  kubectl get poddisruptionbudget -n applications
  kubectl describe pdb nginx-pdb -n applications
    → See ALLOWED DISRUPTIONS (0 or 1 depending on current pod count)"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║                                                              ║${RESET}"
echo -e "${CYAN}${BOLD}║   CURRICULUM COMPLETE - ENTERPRISE K8S RUNNING!             ║${RESET}"
echo -e "${CYAN}${BOLD}║                                                              ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BOLD}Your cluster is fully set up. Here's what you built:${RESET}"
echo ""
kubectl get all -n applications
echo ""
echo -e "${BOLD}Cluster summary:${RESET}"
kubectl get nodes
echo ""
echo -e "${BOLD}All namespaces:${RESET}"
kubectl get namespaces
echo ""
echo -e "${BOLD}Top kubectl commands to practice daily:${RESET}"
echo -e "  ${YELLOW}kubectl get pods -n applications -o wide${RESET}"
echo -e "  ${YELLOW}kubectl describe pod <name> -n applications${RESET}"
echo -e "  ${YELLOW}kubectl logs <pod> -n applications --follow${RESET}"
echo -e "  ${YELLOW}kubectl exec -it <pod> -n applications -- /bin/sh${RESET}"
echo -e "  ${YELLOW}kubectl rollout status deployment/nginx-deployment -n applications${RESET}"
echo -e "  ${YELLOW}kubectl rollout undo deployment/nginx-deployment -n applications${RESET}"
echo -e "  ${YELLOW}kubectl auth can-i list pods --as=<user> -n applications${RESET}"
echo ""
echo -e "${BOLD}When done for the day:${RESET}"
echo -e "  ${YELLOW}bash 01-cluster-setup/destroy-cluster.sh${RESET}   (frees ~2-3 GB RAM)"
echo -e ""
echo -e "${BOLD}Next day:${RESET}"
echo -e "  ${YELLOW}bash 01-cluster-setup/create-cluster.sh${RESET}    (cluster is back in ~90s)"
echo -e "  ${YELLOW}bash run-all.sh${RESET}                              (re-deploy everything)"
echo ""
