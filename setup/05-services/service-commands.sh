#!/usr/bin/env bash
# =============================================================================
# FILE: 05-services/service-commands.sh
# PURPOSE: Deploy Services and teach the full range of service inspection
#          commands. Demonstrate DNS, Endpoints, and traffic routing.
# =============================================================================

set -e
set -u
set -o pipefail

NAMESPACE="applications"
MANIFESTS_DIR="$(dirname "$0")"

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    SERVICE INSPECTION FLOW                                │
# │                                                                           │
# │  Stage 1: Apply Services                                                 │
# │      ├── clusterip-service.yaml (Internal stable IP)                     │
# │      └── nodeport-service.yaml (External port mapping)                   │
# │                                                                           │
# │  Stage 2: Check Service State                                            │
# │      └── kubectl get services                                            │
# │                                                                           │
# │  Stage 3: Inspect Endpoints (The Routing Logic)                          │
# │      └── kubectl get endpoints (Verify Pod IPs are registered)           │
# │                                                                           │
# │  Stage 4: Test CoreDNS                                                   │
# │      └── nslookup from inside a debug pod                                │
# │                                                                           │
# │  Stage 5: Test Traffic Flow                                              │
# │      ├── curl internal ClusterIP                                         │
# │      └── Verify localhost:30000 NodePort works                           │
# └──────────────────────────────────────────────────────────────────────────┘

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
  eval "$@" || true
  echo ""
}

info() {
  echo -e "  ${YELLOW}▸${RESET} $1"
}

# =============================================================================
# STEP 1: APPLY SERVICES
# =============================================================================
section "Step 1: Applying Services"

info "Make sure the nginx deployment is running first..."
kubectl apply -f "${MANIFESTS_DIR}/../04-deployments/nginx-deployment.yaml" \
  -n "${NAMESPACE}" --dry-run=server &>/dev/null || \
  kubectl apply -f "${MANIFESTS_DIR}/../04-deployments/nginx-deployment.yaml" \
  -n "${NAMESPACE}"

info "Applying ClusterIP service..."
run_cmd kubectl apply -f "${MANIFESTS_DIR}/clusterip-service.yaml"

info "Applying NodePort service..."
run_cmd kubectl apply -f "${MANIFESTS_DIR}/nodeport-service.yaml"

echo -e "  ${GREEN}✓ Services applied!${RESET}"

# =============================================================================
# STEP 2: LIST SERVICES
# =============================================================================
section "Step 2: Listing Services"

info "All services in namespace:"
# Columns: NAME, TYPE, CLUSTER-IP, EXTERNAL-IP, PORT(S), AGE
# CLUSTER-IP: The stable virtual IP (never changes, survives pod restarts)
# EXTERNAL-IP: For LoadBalancer type — cloud LB IP. <none> for ClusterIP. <nodes> for NodePort
# PORT(S): "80:30000/TCP" means Service port 80 mapped to NodePort 30000
run_cmd kubectl get services -n "${NAMESPACE}"

info "Wide format (adds selector info):"
run_cmd kubectl get services -n "${NAMESPACE}" -o wide

# =============================================================================
# STEP 3: ENDPOINTS — THE MOST IMPORTANT CONCEPT FOR DEBUGGING
# =============================================================================
section "Step 3: Endpoints — Where Traffic Actually Goes"

info "The ENDPOINTS object is what K8s uses for actual routing:"
# Endpoints lists the ACTUAL Pod IPs and ports that the Service routes to.
# If this list is EMPTY → no pods match the selector → traffic goes nowhere.
# This is the #1 service debugging tool.
#
# WHAT TO CHECK WHEN A SERVICE ISN'T WORKING:
#   1. kubectl get endpoints <service> -n <namespace>
#   2. Is the list empty? → Selector doesn't match any pod labels
#   3. Are pods in the list but not in ReadinessProbe state? → Readiness failing
run_cmd kubectl get endpoints -n "${NAMESPACE}"

info "Describe an endpoint for full details:"
run_cmd kubectl describe endpoints nginx-clusterip -n "${NAMESPACE}"

info "Verify selector matches by checking pods with EXACT same labels:"
# If this list matches the endpoints above → service is wired correctly
run_cmd kubectl get pods -n "${NAMESPACE}" \
  -l "app=nginx,tier=frontend" \
  -o custom-columns="POD:.metadata.name,IP:.status.podIP,READY:.status.containerStatuses[0].ready"

# =============================================================================
# STEP 4: DNS RESOLUTION (the magic of K8s service discovery)
# =============================================================================
section "Step 4: CoreDNS — Service Discovery in Action"

info "Test DNS resolution from inside a pod:"
# Exec into the platform-debug-toolbox pod and run nslookup
# This is how microservices find each other in production
# "nginx-clusterip" resolves to the Service's ClusterIP (the stable virtual IP)
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  nslookup nginx-clusterip.applications.svc.cluster.local

info "Short name resolution (works from within same namespace):"
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  nslookup nginx-clusterip

info "What's in /etc/resolv.conf inside the pod:"
# This shows the search domains that allow short DNS names to work
# K8s injects these into every pod automatically via CoreDNS
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- cat /etc/resolv.conf

# =============================================================================
# STEP 5: TEST CONNECTIVITY
# =============================================================================
section "Step 5: Testing Traffic Flow"

info "Access nginx via ClusterIP service from INSIDE the cluster:"
# curl from platform-debug-toolbox pod → nginx-clusterip service → nginx-deployment pods
# The service acts as a load balancer — each call may hit a different pod
CLUSTER_IP=$(kubectl get service nginx-clusterip -n "${NAMESPACE}" \
  -o jsonpath='{.spec.clusterIP}')
echo -e "  Service ClusterIP: ${YELLOW}${CLUSTER_IP}${RESET}"
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  curl -s --max-time 5 "http://${CLUSTER_IP}" | head -5

info "Access via service NAME (CoreDNS resolves it):"
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  curl -s --max-time 5 "http://nginx-clusterip" | head -5

info "Access via NodePort from YOUR machine (outside the cluster):"
echo ""
echo -e "  ${GREEN}Open your browser: http://localhost:30000${RESET}"
echo -e "  ${GREEN}Or run: curl http://localhost:30000${RESET}"
echo ""
echo -e "  Traffic path:"
echo -e "    Your machine:30000"
echo -e "    → Docker (port mapping from kind-cluster-config.yaml)"
echo -e "    → kind control-plane container:30000"
echo -e "    → kube-proxy iptables rule"
echo -e "    → nginx Pod IP:80"

# =============================================================================
# STEP 6: SERVICE ACCOUNT AND KUBE API ACCESS
# =============================================================================
section "Step 6: The kubernetes Service (Built-in)"

info "There's a special 'kubernetes' service in the default namespace:"
# This service provides pods with access to the Kubernetes API server.
# When your app needs to call the K8s API (e.g., operator, sidecar injector),
# it talks to "kubernetes.default.svc.cluster.local" → API server.
# Authentication is done via the pod's ServiceAccount token (auto-mounted).
run_cmd kubectl get service kubernetes -n default
run_cmd kubectl describe service kubernetes -n default

# =============================================================================
# STEP 7: DEBUGGING SERVICE ISSUES
# =============================================================================
section "Step 7: Service Debugging Runbook"

echo -e "  ${BOLD}If a service is not routing traffic correctly:${RESET}"
echo ""
echo -e "  ${BOLD}Step 1: Check if service exists${RESET}"
echo -e "  kubectl get svc <name> -n <namespace>"
echo ""
echo -e "  ${BOLD}Step 2: Check endpoints (are pods selected?)${RESET}"
echo -e "  kubectl get endpoints <name> -n <namespace>"
echo -e "  → Empty endpoints = selector doesn't match any pod labels"
echo ""
echo -e "  ${BOLD}Step 3: Verify pod labels match service selector${RESET}"
echo -e "  kubectl get pods -n <namespace> -l <selector-from-service>"
echo -e "  kubectl describe svc <name> -n <namespace> | grep Selector"
echo ""
echo -e "  ${BOLD}Step 4: Check pod readiness${RESET}"
echo -e "  kubectl get pods -n <namespace>  (READY column must show 1/1)"
echo -e "  → Not Ready pods are excluded from endpoints automatically"
echo ""
echo -e "  ${BOLD}Step 5: Test connectivity from inside cluster${RESET}"
echo -e "  kubectl run debug --image=busybox -it --rm --restart=Never -- wget -O- http://<service>"
echo ""
echo -e "  ${BOLD}Step 6: Check kube-proxy logs (on the relevant node)${RESET}"
echo -e "  kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50"
echo ""

echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  ✓ Services are configured and tested!${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Next step:${RESET} bash 06-configmaps-secrets/apply-config.sh"
echo ""
