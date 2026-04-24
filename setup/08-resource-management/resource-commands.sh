#!/usr/bin/env bash
# =============================================================================
# FILE: 08-resource-management/resource-commands.sh
# PURPOSE: Demonstrate ResourceQuotas and LimitRanges. Shows how platform
#          teams protect the cluster from resource exhaustion.
# =============================================================================

set -euo pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    RESOURCE MANAGEMENT FLOW                               │
# │                                                                           │
# │  Stage 1: Apply Resource Policies                                        │
# │      ├── Apply resource-quota.yaml                                       │
# │      └── Apply limit-range.yaml                                          │
# │                                                                           │
# │  Stage 2: Deploy Workload                                                │
# │      └── Apply deployment-with-limits.yaml                               │
# │                                                                           │
# │  Stage 3: Inspect Quota Usage                                            │
# │      └── Describe ResourceQuota (Shows Used vs Hard limit)               │
# │                                                                           │
# │  Stage 4: Verify LimitRange Injection                                    │
# │      └── Describe a Pod to see injected/enforced limits                  │
# └──────────────────────────────────────────────────────────────────────────┘

NAMESPACE="applications"
MANIFESTS_DIR="$(dirname "$0")"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Resource Management Demonstration${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"

echo ""
echo -e "${BOLD}Stage 1.0 - Apply Resource Policies${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/resource-quota.yaml"
kubectl apply -f "${MANIFESTS_DIR}/limit-range.yaml"

echo ""
echo -e "${BOLD}Stage 2.0 - Deploy Workload${RESET}"
echo -e "  ${YELLOW}▸ Deploying a compliant workload...${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/deployment-with-limits.yaml"

echo -e "  ${YELLOW}▸ Waiting for deployment rollout...${RESET}"
kubectl rollout status deployment/limited-app -n "${NAMESPACE}" --timeout=60s || true

echo ""
echo -e "${BOLD}Stage 3.0 - Inspect Quota Usage${RESET}"
echo -e "  ${YELLOW}▸ Executing: kubectl describe quota app-namespace-quota -n ${NAMESPACE}${RESET}"
echo -e "  ${YELLOW}▸ Notice how 'Used' compares to the 'Hard' limit.${RESET}"
echo ""
kubectl describe quota app-namespace-quota -n "${NAMESPACE}"

echo ""
echo -e "${BOLD}Stage 4.0 - Verify LimitRange bounds${RESET}"
echo -e "  ${YELLOW}▸ If a pod asks for more than LimitRange allows, it is rejected.${RESET}"
echo -e "  ${YELLOW}▸ Testing a rejection (Dry Run)...${RESET}"
echo ""
cat <<EOF | kubectl apply -n "${NAMESPACE}" --dry-run=server -f - || true
apiVersion: v1
kind: Pod
metadata:
  name: limit-test-pod
spec:
  containers:
  - name: test
    image: busybox
    resources:
      requests:
        cpu: "3" # Exceeds the LimitRange max allowed per container
EOF

echo ""
echo -e "${GREEN}✓ Resource management demonstration complete!${RESET}"
echo ""
echo -e "  ${BOLD}Clean up command (optional):${RESET}"
echo -e "  kubectl delete -f ${MANIFESTS_DIR}/deployment-with-limits.yaml"
echo ""
echo -e "  ${BOLD}Next step:${RESET} 09-health-checks/README.md"
echo ""
