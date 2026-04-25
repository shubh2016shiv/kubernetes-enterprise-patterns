#!/usr/bin/env bash
# =============================================================================
# FILE:    check-and-start-mlflow_1.sh
# PURPOSE: Ensure MLflow server is running for inference operations.
#          If already running, log the URL. If not, start it.
# USAGE:   bash check-and-start-mlflow_1.sh
# OUTPUT:  MLflow UI available at http://127.0.0.1:5000
# =============================================================================

set -euo pipefail

# CAN BE CHANGED: MLflow host binding. `127.0.0.1` is local-only (safe default).
# Example: `0.0.0.0` if other machines on your LAN need to reach the UI.
# If changed, update MLFLOW_TRACKING_URI in your .env files.
MLFLOW_HOST="127.0.0.1"
# CAN BE CHANGED: MLflow port. Example: `5001` if 5000 is already occupied.
# If changed, update MLFLOW_TRACKING_URI in your .env files (e.g., http://127.0.0.1:5001)
# and the URL in all README commands that reference this server.
MLFLOW_PORT="5000"
MLFLOW_URL="http://${MLFLOW_HOST}:${MLFLOW_PORT}"

# ---------------------------------------------------------------------------
# Stage 1: Check if MLflow is already running
# ---------------------------------------------------------------------------
echo "[INFO] Checking if MLflow is already running at ${MLFLOW_URL}..."

if curl -s -I "${MLFLOW_URL}" >/dev/null 2>&1; then
  echo "[OK] MLflow is already running."
  echo "[INFO] Tracking URI:  ${MLFLOW_URL}"
  echo "[INFO] Artifacts:     ${MLFLOW_URL}/api/2.0/mlflow-artifacts/"
  echo "[INFO] UI:            ${MLFLOW_URL}"
  exit 0
fi

echo "[INFO] MLflow is not running. Starting it now..."

# ---------------------------------------------------------------------------
# Stage 2: Preflight checks
# ---------------------------------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  echo "[ERROR] uv is not installed or not on PATH inside WSL2."
  echo
  echo "Install uv from WSL2 Ubuntu with:"
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  echo "  source \"\$HOME/.local/bin/env\""
  echo
  exit 1
fi

echo "[OK] uv found: $(uv --version)"

# ---------------------------------------------------------------------------
# Stage 3: Prepare local MLflow storage (portable location)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CAN BE CHANGED: Hidden server data folder name. Example: `.mlflow-data`.
# Changing this moves where SQLite and artifacts are stored.
MLFLOW_DIR="${SCRIPT_DIR}/.mlflow-server"
BACKEND_DIR="${MLFLOW_DIR}/backend"
# CAN BE CHANGED: Artifact storage folder. Must match artifact_store_root in
# ml-training/configs/training_pipeline.yaml if both modules share one MLflow.
ARTIFACT_DIR="${MLFLOW_DIR}/artifacts"
BACKEND_URI="sqlite:///${BACKEND_DIR}/mlflow.db"

mkdir -p "${BACKEND_DIR}" "${ARTIFACT_DIR}"
echo "[OK] MLflow backend directory: ${BACKEND_DIR}"
echo "[OK] MLflow artifact directory: ${ARTIFACT_DIR}"

# ---------------------------------------------------------------------------
# Stage 4: Start MLflow server
# ---------------------------------------------------------------------------
echo "[INFO] Starting MLflow server"
echo "[INFO] Tracking URI:  ${MLFLOW_URL}"
echo "[INFO] Artifacts:     ${MLFLOW_URL}/api/2.0/mlflow-artifacts/"
echo "[INFO] Press Ctrl+C to stop"
echo "[INFO] Open browser only after you see: 'Listening at: http://127.0.0.1:5000'"

cd "${SCRIPT_DIR}"

# Use environment variable to point to WSL2-specific venv (if needed)
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  export UV_PROJECT_ENVIRONMENT="${MLFLOW_DIR}/.venv-wsl2"
fi

exec uv run --extra tracking mlflow server \
  --backend-store-uri "${BACKEND_URI}" \
  --artifacts-destination "${ARTIFACT_DIR}" \
  --serve-artifacts \
  --host "${MLFLOW_HOST}" \
  --port "${MLFLOW_PORT}"
