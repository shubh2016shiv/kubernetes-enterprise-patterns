# =============================================================================
# FILE:    Dockerfile
# PURPOSE: Build the patient-record-api container image used by Kubernetes.
# USAGE:   docker build -t patient-record-api:1.0.0 .
# WHEN:    app_k8_deployment - before loading the image into the kind cluster.
# PREREQS: Docker Desktop is running with WSL2 integration enabled.
# OUTPUT:  A small FastAPI image that can be scheduled as a Kubernetes pod.
# =============================================================================

# ENTERPRISE EMPHASIS: Pin the Python runtime version instead of using `latest`.
# Production CI/CD systems need repeatable builds, vulnerability scans, and a
# predictable base image lifecycle. Floating tags make incident response harder.
FROM python:3.12.8-slim

# ENTERPRISE EMPHASIS: Keep the runtime directory explicit. This makes image
# scanning, debugging, and shell inspection easier for platform teams.
WORKDIR /opt/patient-record-api

# ENTERPRISE EMPHASIS: Install dependencies before copying application code so
# Docker can reuse the dependency layer when only business code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt

COPY app ./app

# ENTERPRISE EMPHASIS: Application containers should not run as root. The
# Kubernetes Deployment also enforces this with a pod securityContext so the
# image and runtime policy agree.
RUN groupadd --system --gid 10001 patientapi \
    && useradd --system --uid 10001 --gid patientapi --home-dir /opt/patient-record-api patientapi \
    && chown -R patientapi:patientapi /opt/patient-record-api

ENV PYTHONUNBUFFERED=1
ENV API_HOST=0.0.0.0
ENV API_PORT=8080

# LEARNER NOTE: A FastAPI backend image should still be runnable as a normal
# container, but it is not "connected to Kubernetes" by importing Kubernetes
# code. Kubernetes connects to the backend through standard container contracts:
#   1. The process listens on a network interface and port.
#   2. The Deployment starts that process inside pods.
#   3. The Service sends traffic to the pod port.
#   4. ConfigMaps and Secrets inject runtime settings as environment variables.
#
# The critical backend setting is `--host 0.0.0.0` in the CMD below. If Uvicorn
# listened only on 127.0.0.1, it would accept traffic only from inside the same
# container. Kubernetes Services need the app to listen on the pod network
# interface, so 0.0.0.0 is the standard containerized API pattern.
#
# ENTERPRISE EMPHASIS: The container exposes the port the Kubernetes Service
# targets. The Service owns cluster routing; this line documents intent.
EXPOSE 8080

USER patientapi

CMD ["python", "-m", "uvicorn", "app.main:create_application", "--factory", "--host", "0.0.0.0", "--port", "8080"]
