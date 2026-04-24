# =============================================================================
# FILE: ml-serving/05-custom-fastapi-serving/runtime-image/Dockerfile
# PURPOSE: Build the custom FastAPI inference image for the contrast-study path.
#
# ENTERPRISE CONTAINER BEST PRACTICES IMPLEMENTED HERE:
#   1. Multi-stage builds: Separate build dependencies from runtime dependencies.
#      Keeps the final image small and reduces attack surface (no compilers).
#   2. Non-root user: Containers should NEVER run as root in production.
#   3. Python optimizations: PYTHONDONTWRITEBYTECODE, PYTHONUNBUFFERED.
#   4. Explicit workdir and PATH management.
#   5. Tini: Process init system to handle PID 1 zombie reaping and SIGTERM.
#   6. Explicit HEALTHCHECK (useful for Docker, though K8s uses its own probes).
#
# NOTE ON THE LOCAL LEARNING TRADEOFF:
#   The KServe path in this repository already teaches externalized model
#   storage via PVC-backed artifacts. For this custom FastAPI contrast study we
#   deliberately bundle the small model artifact into the image so the learner
#   can focus on the runtime and Deployment mechanics without also fighting
#   local host-path or object-storage setup.
# =============================================================================

# ─── STAGE 1: BUILDER ─────────────────────────────────────────────────────────
# Use the slim version. Alpine is often problematic with Python ML libraries
# (numpy/pandas) because of musl libc vs glibc differences, causing slow
# compile-from-source instead of using pre-built wheels.
FROM python:3.11-slim-bookworm AS builder

# Set environment variables for builder
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install build dependencies if needed (e.g., for libraries without wheels)
# RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev

WORKDIR /build

# Create a virtual environment.
# Why? We can simply copy the entire /opt/venv directory into the final stage,
# cleanly isolating our dependencies from system Python packages.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install dependencies
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# ─── STAGE 2: RUNTIME ─────────────────────────────────────────────────────────
FROM python:3.11-slim-bookworm

# Add labels for enterprise container registries (Harbor, ECR, GCR)
LABEL maintainer="ML Platform Team" \
      version="1.0.0" \
      description="FastAPI Inference Server for Wine Quality Classification" \
      org.opencontainers.image.source="https://github.com/company/ml-repo"

# Python runtime optimizations
# PYTHONUNBUFFERED=1 : Force stdout/stderr to be unbuffered.
#                      Ensures logs are instantly sent to K8s log collector,
#                      not trapped in a buffer if the app crashes.
# PYTHONDONTWRITEBYTECODE=1 : Don't write .pyc files (useless in ephemeral containers).
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH="/app" \
    # App configuration (can be overridden by K8s ConfigMap)
    PORT=8000 \
    APP_VERSION="1.0.0" \
    # The expected path where K8s will mount the model artifact
    MODEL_PATH="/models/model.pkl" \
    MODEL_METADATA_PATH="/models/model_metadata.json"

# Install tini (process manager) and minimal runtime dependencies
# tini is crucial: it handles SIGTERM correctly from Kubernetes, ensuring
# graceful shutdown of the FastAPI/Uvicorn process.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user (security best practice)
# uid=10001 is standard. Avoid uid=1000 as it sometimes overlaps with host users.
RUN groupadd -g 10001 mlapp && \
    useradd -u 10001 -g mlapp -s /bin/bash -m mlapp

# Create directories and set ownership
WORKDIR /app
RUN mkdir -p /models && \
    chown -R mlapp:mlapp /app /models

# Copy the pre-built virtual environment from the builder stage
COPY --from=builder --chown=mlapp:mlapp /opt/venv /opt/venv

# Copy application code
# Notice we copy app/ into /app/app to maintain Python module structure
COPY --chown=mlapp:mlapp app /app/app
COPY --chown=mlapp:mlapp model/artifacts /models

# Switch to the non-root user BEFORE running any application code
USER 10001:10001

# Expose the port (documentation only, K8s Service handles actual routing)
EXPOSE 8000

# Optional: Docker healthcheck (K8s will ignore this and use its own probes,
# but useful if running locally via docker run)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["curl", "-f", "http://localhost:8000/health"] || exit 1

# Use tini as the entrypoint to handle PID 1 responsibilities
ENTRYPOINT ["/usr/bin/tini", "--"]

# Run uvicorn.
# --host 0.0.0.0 : Bind to all interfaces (required inside containers)
# --port 8000    : Listen port
# --workers 1    : In K8s, we scale horizontally via Pod replicas, not workers.
#                  1 worker = 1 model loaded in RAM = predictable memory usage.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
