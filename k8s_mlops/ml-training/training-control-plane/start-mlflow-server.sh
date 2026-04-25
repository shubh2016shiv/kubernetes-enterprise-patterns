#!/usr/bin/env bash
# =============================================================================
# FILE:    start-mlflow-server.sh
# PURPOSE: Start a local MLflow Tracking and Model Registry server for the
#          training control-plane lab.
# USAGE:   ./start-mlflow-server.sh
# WHEN:    Run before launching a candidate training job that should publish
#          metrics, artifacts, and model registry metadata to MLflow.
# PREREQS: WSL2 Ubuntu shell, uv installed in WSL2, and network access if
#          MLflow has not already been installed in the project environment.
# OUTPUT:  MLflow UI available at http://127.0.0.1:5000.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
#   Stage 1: Resolve paths
#       - Find the ml-training module root from this script location.
#
#   Stage 2: Preflight checks
#       - Verify uv is installed in WSL2.
#       - Force a WSL2-specific virtual environment so Linux does not reuse
#         a Windows .venv created by PowerShell.
#
#   Stage 3: Prepare local MLflow storage
#       - Create SQLite backend and artifact directories.
#
#   Stage 4: Start MLflow server
#       - Run an HTTP server that the training pipeline can publish to.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Stage 1.0: Resolve paths
# Purpose: Make the script runnable from any current working directory.
# Expected input: This file lives under ml-training/training-control-plane.
# Expected output: PROJECT_ROOT points at the ml-training module.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/mlflow-tracking/backend"
ARTIFACT_DIR="${PROJECT_ROOT}/mlflow-tracking/artifacts"
BACKEND_URI="sqlite:///${BACKEND_DIR}/mlflow.db"
ARTIFACT_ROOT="${ARTIFACT_DIR}"
WSL2_VENV_DIR="${PROJECT_ROOT}/.venv-wsl2"

echo "[INFO] MLflow local server for the training control plane"
echo "[INFO] Project root: ${PROJECT_ROOT}"

# ---------------------------------------------------------------------------
# Stage 2.0: Preflight checks
# Purpose: Fail early with a teachable message if the local WSL2 toolchain is
#          missing before we attempt to start MLflow.
# Expected input: uv is installed inside WSL2, not only on Windows.
# Expected output: uv is available on PATH, or the script exits with the exact
#                  install command to run next.
# ---------------------------------------------------------------------------

# Stage 2.1: Check uv
# Why: This repository uses uv to create the Python environment and install the
#      optional MLflow tracking dependencies. Windows and WSL2 have separate
#      PATH values, so uv installed on Windows does not automatically exist
#      inside Ubuntu.
if ! command -v uv >/dev/null 2>&1; then
  echo "[ERROR] uv is not installed or not on PATH inside WSL2."
  echo
  echo "Why this matters:"
  echo "  MLflow is an optional training dependency. This script starts it via:"
  echo "    uv run --extra tracking mlflow server ..."
  echo "  Without uv, WSL2 cannot create the project environment or install MLflow."
  echo
  echo "Run this from WSL2 Ubuntu, then reopen the terminal or source your shell profile:"
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  echo "  source \"\$HOME/.local/bin/env\""
  echo
  echo "Then retry:"
  echo "  bash k8s_mlops/ml-training/training-control-plane/start-mlflow-server.sh"
  exit 1
fi

echo "[OK] uv found: $(uv --version)"

# Stage 2.2: Use a WSL2-specific Python environment
# Why: This repository may also be opened from Windows PowerShell. A Windows
#      `.venv` contains Windows executables under Scripts/, while WSL2 needs
#      Linux executables under bin/. Reusing the wrong environment causes slow
#      installs, confusing "command not found" errors, or silent hangs.
export UV_PROJECT_ENVIRONMENT="${WSL2_VENV_DIR}"
echo "[OK] WSL2 Python environment path: ${UV_PROJECT_ENVIRONMENT}"

# ---------------------------------------------------------------------------
# Stage 3.0: Prepare local MLflow storage
# Purpose: Create durable local folders before the server starts.
# Expected input: The learner has write access to the ml-training directory.
# Expected output: SQLite database and artifact folders can be created by MLflow.
# ---------------------------------------------------------------------------
mkdir -p "${BACKEND_DIR}" "${ARTIFACT_DIR}"
echo "[OK] MLflow backend directory exists: ${BACKEND_DIR}"
echo "[OK] MLflow artifact directory exists: ${ARTIFACT_DIR}"

# ---------------------------------------------------------------------------
# Stage 4.0: Start MLflow server
# Purpose: Provide the UI and API endpoint that training runs publish to.
# Expected input: uv can run the optional mlflow dependency.
# Expected output: MLflow listens on http://127.0.0.1:5000 until you stop it.
# ---------------------------------------------------------------------------
cd "${PROJECT_ROOT}"

echo "[INFO] Starting MLflow server"
echo "[INFO] Tracking URI for training runs: http://127.0.0.1:5000"
echo "[INFO] Artifact proxy:  http://127.0.0.1:5000/api/2.0/mlflow-artifacts/"
echo "[INFO] Press Ctrl+C to stop the server"
echo "[INFO] First run note: uv may spend a few minutes installing MLflow."
echo "[INFO] Open the browser only after you see a line like:"
echo "       Listening at: http://127.0.0.1:5000"

# ---------------------------------------------------------------------------
# Why --serve-artifacts matters for this Windows + WSL2 lab:
#
#   Without --serve-artifacts, MLflow stores artifacts as raw filesystem paths
#   such as /mnt/d/... (a WSL2 Linux path). When a Windows Python client or
#   the serving pipeline later resolves the registered model URI
#   (models:/wine-quality-classifier/1), it tries to open that Linux path on
#   Windows and gets D:\mnt\d\... which does not exist. Artifact downloads
#   fail silently or with a confusing permission error.
#
#   With --serve-artifacts, the server becomes the artifact proxy. The artifact
#   URI in every run record becomes mlflow-artifacts:/ (an HTTP-relative
#   scheme). Any client -- Windows, WSL2, or a container -- fetches artifacts
#   through http://127.0.0.1:5000 without ever needing direct filesystem
#   access. The server is the only process that touches the local artifact
#   directory.
#
#   --artifacts-destination tells the server WHERE to store artifact bytes on
#   the server's own filesystem. This replaces --default-artifact-root when
#   artifact proxying is active. The server maps the HTTP artifact URL to this
#   local directory internally.
#
# ENTERPRISE EQUIVALENT:
#   In production, --artifacts-destination is replaced by an S3 bucket URI,
#   a Google Cloud Storage bucket, or an Azure Blob Storage container. The
#   serving pipeline still fetches artifacts from the MLflow tracking URI --
#   the storage backend is completely transparent to it. This is exactly why
#   the pattern below maps cleanly to an enterprise deployment.
# ---------------------------------------------------------------------------

# Expected output:
#   [INFO] Starting gunicorn ...
#   Listening at: http://127.0.0.1:5000
exec uv run --extra tracking mlflow server \
  --backend-store-uri "${BACKEND_URI}" \
  --artifacts-destination "${ARTIFACT_ROOT}" \
  --serve-artifacts \
  --host 127.0.0.1 \
  --port 5000
