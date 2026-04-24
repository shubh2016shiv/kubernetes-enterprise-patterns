#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/05-custom-fastapi-serving/kubernetes-manifests/apply-stack.sh
# PURPOSE: Deploys the ML inference architecture to the cluster and runs a
#          health verification check.
# =============================================================================

set -e
set -u
set -o pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

NAMESPACE="applications"
MANIFESTS_DIR="$(dirname "$0")"
REPO_ROOT="$(cd "${MANIFESTS_DIR}/../.." && pwd)"

echo -e "${CYAN}${BOLD}======================================================${RESET}"
echo -e "${CYAN}${BOLD}  Deploying ML Inference Architecture                 ${RESET}"
echo -e "${CYAN}${BOLD}======================================================${RESET}"
echo ""

# Ensure namespaces exist (dependency)
kubectl apply -f "${REPO_ROOT}/setup/02-namespaces/namespaces.yaml" > /dev/null

echo -e "${BOLD}[1/4] Applying application configuration...${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/01-application-config.yaml"
echo -e "${GREEN}✓ Configuration applied.${RESET}"
echo ""

echo -e "${BOLD}[2/4] Applying custom FastAPI Deployment...${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/02-inference-deployment.yaml"
echo -e "${GREEN}✓ Deployment applied.${RESET}"
echo ""

echo -e "${BOLD}[3/4] Applying Service and HPA...${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/03-service-and-hpa.yaml"
echo -e "${GREEN}✓ Service (NodePort 30001) and HPA applied.${RESET}"
echo ""

echo -e "${BOLD}[4/4] Waiting for pods to become Ready...${RESET}"
echo -e "${YELLOW}Note: This may take ~10-20s while the FastAPI server boots and loads the model.${RESET}"
echo ""

# Watch the rollout status
kubectl rollout status deployment/wine-quality-fastapi-serving -n "${NAMESPACE}" --timeout=120s

echo ""
echo -e "${CYAN}${BOLD}======================================================${RESET}"
echo -e "${CYAN}${BOLD}  Deployment Complete & Healthy!                      ${RESET}"
echo -e "${CYAN}${BOLD}======================================================${RESET}"
echo ""
echo -e "${BOLD}Check Pod Status:${RESET}"
kubectl get pods -n "${NAMESPACE}" -l app=wine-quality-fastapi-serving -o wide
echo ""
echo -e "${BOLD}Check HPA Status:${RESET}"
kubectl get hpa wine-quality-fastapi-hpa -n "${NAMESPACE}"
echo ""
echo -e "${BOLD}Test the API locally:${RESET}"
echo -e "  ${GREEN}Docs:    http://localhost:30001/docs${RESET}"
echo -e "  ${GREEN}Metrics: http://localhost:30001/metrics${RESET}"
echo -e "  ${GREEN}Info:    http://localhost:30001/model/info${RESET}"
echo ""
echo -e "To send a prediction request, run:"
echo -e "  ${YELLOW}bash ml-serving/05-custom-fastapi-serving/kubernetes-manifests/test-inference.sh${RESET}"
echo ""
