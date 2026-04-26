#!/usr/bin/env bash
# =============================================================================
# FILE:    commands.sh
# PURPOSE: Apply Services for both sibling Deployments, inspect endpoint
#          registration, test CoreDNS, and prove that one Deployment can call
#          another through stable Service DNS names.
# USAGE:   bash setup/05-services/commands.sh
# WHEN:    Run this after the deployment module has created the gateway and backend Deployments.
# PREREQS: Namespace `applications` exists, both Deployments exist or can be
#          applied, and platform-debug-toolbox pod exists for in-cluster checks.
# OUTPUT:  Three Services created, endpoints populated, DNS resolution succeeds,
#          and gateway-to-backend communication works through Services.
# =============================================================================

set -euo pipefail

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                           SCRIPT FLOW                                     │
# │                                                                            │
# │  Stage 1: Apply Services                                                  │
# │      └── Create internal Services for both Deployments and a NodePort      │
# │                                                                            │
# │  Stage 2: Inspect Service State                                           │
# │      └── List Services and confirm stable IP/port exposure                 │
# │                                                                            │
# │  Stage 3: Inspect Endpoints                                               │
# │      └── Verify ready pod IPs are registered for both Services            │
# │                                                                            │
# │  Stage 4: Test CoreDNS                                                    │
# │      └── Resolve both Service names from inside a pod                      │
# │                                                                            │
# │  Stage 5: Test Communication Paths                                        │
# │      └── Call backend directly and then call it again through gateway      │
# │                                                                            │
# │  Stage 6: Learn the Debugging Runbook                                     │
# │      └── Review the production-style checks for broken Service traffic     │
# └────────────────────────────────────────────────────────────────────────────┘

# CONFIGURATION EXPLANATION `applications` is where the Deployments and Services live together. Services only
# select pods in their own namespace unless you build more advanced cross-namespace
# patterns, so this value keeps networking tests pointed at the right workloads.
NAMESPACE="applications"
MANIFESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "\$ $*"
  "$@"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1.0: Apply Services
# Purpose: Create stable identities for both sibling Deployments.
# Expected output: gateway ClusterIP, backend ClusterIP, and gateway NodePort exist.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 1.0: Apply Services"

echo "Ensuring both Deployments exist before wiring Services to them."
kubectl apply -f "${MANIFESTS_DIR}/../04-deployments/risk-profile-api-deployment.yaml" \
  -n "${NAMESPACE}" >/dev/null
kubectl apply -f "${MANIFESTS_DIR}/../04-deployments/inference-gateway-deployment.yaml" \
  -n "${NAMESPACE}" >/dev/null

run_cmd kubectl apply -f "${MANIFESTS_DIR}/risk-profile-api-clusterip.yaml"
run_cmd kubectl apply -f "${MANIFESTS_DIR}/clusterip-service.yaml"
run_cmd kubectl apply -f "${MANIFESTS_DIR}/nodeport-service.yaml"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2.0: Inspect Service State
# Purpose: Show the stable network identities created by Kubernetes.
# Expected output: two ClusterIP services and one NodePort service.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 2.0: Inspect Service State"

run_cmd kubectl get services -n "${NAMESPACE}"
run_cmd kubectl get services -n "${NAMESPACE}" -o wide

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3.0: Inspect Endpoints
# Purpose: Show where traffic really goes after it hits a Service.
# Expected output: gateway endpoints on 8080 and backend endpoints on 8081.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 3.0: Inspect Endpoints"

run_cmd kubectl get endpoints -n "${NAMESPACE}"
run_cmd kubectl describe endpoints inference-gateway-clusterip -n "${NAMESPACE}"
run_cmd kubectl describe endpoints risk-profile-api-clusterip -n "${NAMESPACE}"

run_cmd kubectl get pods -n "${NAMESPACE}" \
  -l "app=inference-gateway,tier=backend" \
  -o custom-columns="POD:.metadata.name,IP:.status.podIP,READY:.status.containerStatuses[0].ready"

run_cmd kubectl get pods -n "${NAMESPACE}" \
  -l "app=risk-profile-api,tier=backend" \
  -o custom-columns="POD:.metadata.name,IP:.status.podIP,READY:.status.containerStatuses[0].ready"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4.0: Test CoreDNS
# Purpose: Show that pods resolve Services by stable DNS names.
# Expected output: both Service names resolve successfully.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 4.0: Test CoreDNS"

run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  nslookup inference-gateway-clusterip.applications.svc.cluster.local

run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  nslookup risk-profile-api-clusterip.applications.svc.cluster.local

run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- cat /etc/resolv.conf

# ─────────────────────────────────────────────────────────────────────────────
# Stage 5.0: Test Communication Paths
# Purpose: Prove direct backend access and indirect gateway-to-backend access.
# Expected output: backend returns JSON directly, and gateway returns dependency-check JSON.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 5.0: Test Communication Paths"

GATEWAY_CLUSTER_IP=$(kubectl get service inference-gateway-clusterip -n "${NAMESPACE}" \
  -o jsonpath='{.spec.clusterIP}')
BACKEND_CLUSTER_IP=$(kubectl get service risk-profile-api-clusterip -n "${NAMESPACE}" \
  -o jsonpath='{.spec.clusterIP}')

echo "Gateway Service ClusterIP: ${GATEWAY_CLUSTER_IP}"
echo "Backend Service ClusterIP: ${BACKEND_CLUSTER_IP}"
echo ""

echo "Direct call from debug pod to backend Service:"
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  wget -qO- "http://risk-profile-api-clusterip/profile/rules"

echo "Call from debug pod to gateway Service, where gateway then calls the backend Service:"
run_cmd kubectl exec platform-debug-toolbox -n "${NAMESPACE}" -- \
  wget -qO- "http://inference-gateway-clusterip/dependencies"

echo "From your machine, this is the local external path:"
echo "  curl http://localhost:30000/dependencies"
echo "  or open http://localhost:30000/dependencies in a browser"
echo ""
echo "Traffic path:"
echo "  laptop -> localhost:30000 -> gateway Service -> gateway pod"
echo "  gateway pod -> risk-profile-api-clusterip -> ready backend pod"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 6.0: Service Debugging Runbook
# Purpose: Leave the learner with a production-style troubleshooting checklist.
# Expected output: a clear order of checks for broken service-to-service traffic.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 6.0: Service Debugging Runbook"

echo "1. Check the Service object:"
echo "   kubectl get svc <name> -n <namespace>"
echo ""
echo "2. Check endpoints:"
echo "   kubectl get endpoints <name> -n <namespace>"
echo "   Empty endpoints usually means selector mismatch or pods not Ready."
echo ""
echo "3. Check the backend pods:"
echo "   kubectl get pods -n <namespace> -l <selector> -o wide"
echo ""
echo "4. Check DNS from inside the cluster:"
echo "   kubectl exec <debug-pod> -n <namespace> -- nslookup <service>"
echo ""
echo "5. Check direct backend behavior before blaming the caller:"
echo "   kubectl exec <debug-pod> -n <namespace> -- wget -qO- http://risk-profile-api-clusterip/profile/rules"
echo ""
echo "6. Then check the caller path:"
echo "   kubectl exec <debug-pod> -n <namespace> -- wget -qO- http://inference-gateway-clusterip/dependencies"
echo ""
echo "7. If external access fails, verify the local or cloud entry point:"
echo "   NodePort locally, ALB/GCLB/Application Gateway in enterprise."
echo ""
echo "Next step:"
echo "  bash 06-configmaps-secrets/apply-config.sh"
