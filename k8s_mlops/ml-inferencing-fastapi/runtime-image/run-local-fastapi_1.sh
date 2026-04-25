#!/usr/bin/env bash
# =============================================================================
# FILE:    run-local-fastapi_1.sh
# PURPOSE: Start the FastAPI inference app locally before building the container.
# USAGE:   From WSL2:
#          cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/runtime-image
#          bash run-local-fastapi.sh
# WHEN:    Run this after MLflow is running and after a model version is approved.
# PREREQS: uv installed, MLflow reachable, .env or .env.example present.
# OUTPUT:  Uvicorn starts on http://0.0.0.0:8080 and the app logs model loading.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────┐
# │                    SCRIPT FLOW                                       │
# │                                                                      │
# │  Stage 1: Locate runtime root                                        │
# │      └── Always run from this script's directory                     │
# │                                                                      │
# │  Stage 2: Validate local config                                      │
# │      └── Ensure .env exists and MLflow can be reached                │
# │                                                                      │
# │  Stage 3: Prepare Python runtime                                     │
# │      └── uv sync creates or updates the local virtual environment    │
# │                                                                      │
# │  Stage 4: Start FastAPI                                              │
# │      └── uvicorn loads the MLflow model during application startup   │
# └─────────────────────────────────────────────────────────────────────┘

# CAN BE CHANGED: Host binding for local Uvicorn. `0.0.0.0` allows other
# WSL2 terminals and host-machine browsers to reach it. Use `127.0.0.1` to
# restrict access to localhost only. Override via: APP_HOST=127.0.0.1 bash run-local-fastapi_1.sh
APP_HOST="${APP_HOST:-0.0.0.0}"
# CAN BE CHANGED: Local port Uvicorn listens on. Example: `8090`.
# Must match the containerPort in 05-inference-deployment.yaml and the Dockerfile
# CMD port. If changed, update both of those files.
APP_PORT="${APP_PORT:-8080}"
# CAN BE CHANGED: Path to your local .env config file. Example: `.env.staging`.
# Override via: INFERENCE_ENV_FILE=.env.staging bash run-local-fastapi_1.sh
ENV_FILE="${INFERENCE_ENV_FILE:-.env}"

print_stage() {
  local message="$1"
  printf '\n%s\n' "─────────────────────────────────────────────────────────"
  printf '%s\n' "$message"
  printf '%s\n' "─────────────────────────────────────────────────────────"
}

read_env_value() {
  local key="$1"
  local file="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  grep -E "^${key}=" "$file" | tail -n 1 | cut -d '=' -f 2-
}

# ─────────────────────────────────────────────────────────
# Stage 1.0: Locate Runtime Root
# Purpose: Make the script reliable even when a teammate launches it from a
#          different working directory.
# Expected input: This script lives in runtime-image/.
# Expected output: Current directory becomes runtime-image/.
# ─────────────────────────────────────────────────────────
print_stage "Stage 1.0: Locating FastAPI runtime root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "pyproject.toml" || ! -d "app" ]]; then
  echo "ERROR: This script must live in the runtime-image root next to pyproject.toml and app/."
  echo "Check that you are running: bash run-local-fastapi.sh"
  exit 1
fi

echo "Runtime root: $SCRIPT_DIR"

# ─────────────────────────────────────────────────────────
# Stage 2.0: Validate Local Configuration
# Purpose: Use the same central config contract as Kubernetes, but load values
#          from .env for the local pre-container check.
# Expected input: .env or .env.example.
# Expected output: .env exists and key non-secret values are visible.
# ─────────────────────────────────────────────────────────
print_stage "Stage 2.0: Validating local inference configuration"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ "$ENV_FILE" != ".env" ]]; then
    echo "ERROR: INFERENCE_ENV_FILE points to '$ENV_FILE', but that file does not exist."
    echo "Fix: create the file or unset INFERENCE_ENV_FILE to use .env."
    exit 1
  fi

  if [[ ! -f ".env.example" ]]; then
    echo "ERROR: Neither .env nor .env.example exists."
    echo "Fix: restore .env.example or create .env with MODEL_URI and MLFLOW_TRACKING_URI."
    exit 1
  fi

  cp .env.example .env
  echo "Created .env from .env.example."
  echo "If your approved model is not version 1, edit .env before rerunning this script."
fi

MODEL_URI="$(read_env_value "MODEL_URI" "$ENV_FILE")"
MODEL_VERSION="$(read_env_value "MODEL_VERSION" "$ENV_FILE")"
MLFLOW_TRACKING_URI="$(read_env_value "MLFLOW_TRACKING_URI" "$ENV_FILE")"

echo "Config file: $ENV_FILE"
echo "Model URI: ${MODEL_URI:-missing}"
echo "Model version: ${MODEL_VERSION:-missing}"
echo "MLflow Tracking URI: ${MLFLOW_TRACKING_URI:-missing}"

if [[ -z "${MODEL_URI:-}" || -z "${MLFLOW_TRACKING_URI:-}" ]]; then
  echo "ERROR: MODEL_URI and MLFLOW_TRACKING_URI are required in $ENV_FILE."
  echo "Fix: open $ENV_FILE and set both values before starting FastAPI."
  exit 1
fi

# ─────────────────────────────────────────────────────────
# Stage 2.1: Check Required Tools
# Purpose: Fail early with a clear message instead of surfacing a confusing
#          Python or shell error later.
# Expected input: uv and curl are available in WSL2.
# Expected output: Tool checks pass.
# ─────────────────────────────────────────────────────────
print_stage "Stage 2.1: Checking required local tools"

if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv is not installed or not on PATH."
  echo "Fix: install uv in WSL2, then rerun this script."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is not installed or not on PATH."
  echo "Fix: install curl in WSL2, then rerun this script."
  exit 1
fi

echo "uv: $(uv --version)"
echo "curl: available"

# ─────────────────────────────────────────────────────────
# Stage 2.2: Check MLflow Reachability
# Purpose: Model loading depends on MLflow. If MLflow is down, FastAPI should
#          fail startup rather than sit alive but unusable.
# Expected input: MLflow server running at MLFLOW_TRACKING_URI.
# Expected output: HTTP request succeeds, or the script fails with next steps.
# ─────────────────────────────────────────────────────────
print_stage "Stage 2.2: Checking MLflow reachability"

if ! curl -fsS --max-time 5 "$MLFLOW_TRACKING_URI" >/dev/null; then
  echo "ERROR: MLflow is not reachable at $MLFLOW_TRACKING_URI."
  echo "Fix: start MLflow first, then rerun this script."
  echo "Example check: curl -I $MLFLOW_TRACKING_URI"
  exit 1
fi

echo "MLflow is reachable at $MLFLOW_TRACKING_URI."

# ─────────────────────────────────────────────────────────
# Stage 3.0: Prepare Python Runtime
# Purpose: uv creates a deterministic local virtual environment from
#          pyproject.toml and uv.lock.
# Expected input: pyproject.toml exists.
# Expected output: Dependencies are installed or confirmed current.
# ─────────────────────────────────────────────────────────
print_stage "Stage 3.0: Syncing local Python dependencies with uv"

uv sync

# ENTERPRISE EMPHASIS: If MLflow prints a model dependency mismatch warning
# during startup, treat it as an environment-parity signal. The model may still
# load locally, but a production image should be aligned with the model's logged
# dependency environment or tested with an explicit compatibility gate.

# ─────────────────────────────────────────────────────────
# Stage 4.0: Start FastAPI
# Purpose: Run the same app code that will later be packaged into the inference
#          container image.
# Expected input: .env has a valid immutable MODEL_URI.
# Expected output: Uvicorn starts and logs "Model loaded successfully".
# ─────────────────────────────────────────────────────────
print_stage "Stage 4.0: Starting FastAPI inference app"

echo "Starting Uvicorn on http://${APP_HOST}:${APP_PORT}"
echo "Readiness check from another WSL2 terminal:"
echo "  curl http://127.0.0.1:${APP_PORT}/health/ready"
echo

uv run python -m uvicorn app.main:app --host "$APP_HOST" --port "$APP_PORT"
