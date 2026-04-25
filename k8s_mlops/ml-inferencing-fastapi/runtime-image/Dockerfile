# =============================================================================
# FILE:    Dockerfile
# PURPOSE: Build the container image for the wine quality inference API.
#          This image is separate from the training image. It installs only
#          the serving dependencies (FastAPI, MLflow client, scikit-learn)
#          and does not include training tools (Optuna, hyperopt, etc.).
# WHEN:    Build before pushing to a container registry or loading into kind.
# USAGE (from runtime-image/ directory in WSL2):
#   docker build -t wine-quality-inference-api:1.0.0 .
# LOAD INTO KIND (local lab only):
#   kind load docker-image wine-quality-inference-api:1.0.0 --name local-enterprise-dev
# ENTERPRISE EQUIVALENT: A CI/CD pipeline builds this image on every merge to
#   main, tags it with the Git commit SHA, scans it for vulnerabilities, and
#   pushes it to an OCI-compliant registry (ECR, GCR, ACR, Harbor).
# =============================================================================

# ───────��─────────────────────────────────────────────────────────────────────
# Stage 1: Dependency builder
# Use a full Python image to compile and install Python packages. The result is
# copied to the final slim image so the final image does not carry build tools.
#
# ENTERPRISE EMPHASIS: Multi-stage builds are the standard pattern for
# production Python containers. Without them, the final image would contain
# gcc, make, and header files — tools needed to compile C extensions during
# pip install but not needed at runtime. These tools increase image size and
# attack surface.
# ───────────────────────────────────────────────────���─────────────────────────
FROM python:3.11-slim AS builder

# Prevent Python from writing .pyc bytecode to disk in the builder stage.
# Bytecode is regenerated on first import anyway, and skipping it during
# install slightly speeds up the pip install step.
ENV PYTHONDONTWRITEBYTECODE=1

# Disable stdout/stderr buffering so pip install output appears in build logs
# without delay. Helps CI logs show progress on large package installs.
ENV PYTHONUNBUFFERED=1

WORKDIR /build

# Copy requirements first — before copying application code.
# Docker layer caching: if requirements.txt does not change, Docker reuses the
# cached layer for pip install, making iterative image builds much faster.
COPY requirements.txt .

# Install dependencies into an isolated prefix directory so they can be
# cleanly copied to the final stage with no interference from other packages.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ──────────────────────────────────────────────────���──────────────────────────
# Stage 2: Final runtime image
# Start from the same slim base and copy only the installed packages and the
# application code. The final image has no build tools and no pip cache.
# ────────────────────────────────────────────────────────���────────────────────
FROM python:3.11-slim AS runtime

# ENTERPRISE EMPHASIS: The inference image is separated from the training image
# because production inference containers should be smaller, faster to start,
# and have a reduced attack surface. Training containers need Optuna, hyperopt,
# and dataset libraries that have no place in a serving container.
LABEL org.opencontainers.image.description="Wine quality inference API — serves approved MLflow model versions"
LABEL org.opencontainers.image.source="k8s_mlops/ml-inferencing-fastapi/runtime-image"

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Add the installed packages from the builder stage to the Python path.
ENV PYTHONPATH=/install/lib/python3.11/site-packages

WORKDIR /app

# Create a non-root user and group for the application process.
# ENTERPRISE EMPHASIS: Running as non-root reduces blast radius if the
# container is compromised. Kubernetes PodSecurityStandards (or the deprecated
# PodSecurityPolicy) require non-root execution for most security profiles.
# The UID 10001 is arbitrary but above the reserved range (0–999).
RUN groupadd --gid 10001 inference \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /sbin/nologin inference

# Copy installed Python packages from the builder stage.
COPY --from=builder /install /install

# Copy the application source code.
# Only the app/ directory is needed at runtime — not docs, scripts, or manifests.
COPY app/ ./app/

# Change ownership of the app directory to the non-root user.
RUN chown -R inference:inference /app

# Switch to the non-root user before the final CMD.
USER inference

# Expose the port Uvicorn listens on. This is documentation for docker run
# and for Kubernetes container port declarations. It does not publish the port.
EXPOSE 8080

# Health check for Docker Desktop / docker run (not used by Kubernetes probes,
# which are configured in the Deployment manifest). Useful for local testing.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health/live')"

# Start the Uvicorn ASGI server.
# --host 0.0.0.0: listen on all interfaces (required inside a container).
# --port 8080:    must match the containerPort in the Kubernetes Deployment.
# --workers 1:    a single worker keeps the in-memory model shared within the
#                 process. For multi-core scaling, run multiple pod replicas
#                 rather than multiple workers in one pod. Each worker would
#                 load a separate copy of the model into memory, multiplying
#                 RAM usage per pod unpredictably.
# --log-level warning: Uvicorn's own logs are suppressed in favor of the
#                 application's structured JSON logging.
#
# ENTERPRISE EQUIVALENT: Production often uses gunicorn with a uvicorn worker
# class (gunicorn -k uvicorn.workers.UvicornWorker) to get better process
# supervision and graceful restart on config reload. For single-replica
# GPU-bound serving, uvicorn alone is standard.
CMD ["python", "-m", "uvicorn", "app.main:app",
     "--host", "0.0.0.0",
     "--port", "8080",
     "--workers", "1",
     "--log-level", "warning"]
