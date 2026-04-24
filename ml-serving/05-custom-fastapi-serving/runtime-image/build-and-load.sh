#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/05-custom-fastapi-serving/runtime-image/build-and-load.sh
# PURPOSE: Build the custom FastAPI image and load it into the local kind cluster.
#
# ENTERPRISE CONTEXT:
#   In production, CI/CD (GitHub Actions, GitLab CI) would:
#     1. Build the Docker image
#     2. Run security scans (Trivy, Snyk)
#     3. Push to an enterprise registry (AWS ECR, JFrog Artifactory)
#     4. Kubernetes nodes would pull the image from that registry
#
#   For local development with kind:
#     We don't need a registry! We build the image on the host machine,
#     and use `kind load docker-image` to inject it directly into the
#     virtual nodes' containerd storage. This is much faster.
# =============================================================================

set -e
set -u
set -o pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

IMAGE_NAME="wine-quality-fastapi-serving"
IMAGE_TAG="1.0.0"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
CLUSTER_NAME="local-enterprise-dev"

echo -e "${CYAN}${BOLD}======================================================${RESET}"
echo -e "${CYAN}${BOLD}  Building and Loading ML Inference Container         ${RESET}"
echo -e "${CYAN}${BOLD}======================================================${RESET}"
echo ""

# 1. Build the model artifact first
echo -e "${BOLD}[1/3] Generating ML model artifact...${RESET}"
cd "$(dirname "$0")"
# Install local dependencies to run the training script
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required to build the model artifact locally."
    exit 1
fi

echo "Installing sklearn locally..."
# Use python3 -m pip to avoid PATH issues with just 'pip'
python3 -m pip install -q scikit-learn==1.5.2 numpy pandas joblib || {
    echo "Error: Failed to install Python dependencies. Ensure python3-pip is installed."
    echo "On WSL/Ubuntu: sudo apt-get update && sudo apt-get install python3-pip"
    exit 1
}
echo "Training model..."
python3 model/train_and_save.py
echo -e "${GREEN}✓ Artifacts generated in ml-serving/05-custom-fastapi-serving/runtime-image/model/artifacts/${RESET}"
echo ""

# 2. Build the Docker image
echo -e "${BOLD}[2/3] Building Docker image ${FULL_IMAGE}...${RESET}"
# This uses the Dockerfile in the current directory
docker build -t "${FULL_IMAGE}" .
echo -e "${GREEN}✓ Docker image built successfully.${RESET}"
echo ""

# 3. Load into kind cluster
echo -e "${BOLD}[3/3] Loading image into kind cluster '${CLUSTER_NAME}'...${RESET}"
if ! command -v kind &> /dev/null; then
    echo "Error: kind CLI not found."
    exit 1
fi

# The --name must match the cluster name defined in setup/01-cluster-setup/create-cluster.sh
kind load docker-image "${FULL_IMAGE}" --name "${CLUSTER_NAME}"

echo -e "${GREEN}✓ Image loaded into all cluster nodes.${RESET}"
echo ""
echo -e "${CYAN}${BOLD}Next step:${RESET} Apply the Kubernetes manifests"
echo "cd ../kubernetes-manifests"
echo "bash apply-stack.sh"
