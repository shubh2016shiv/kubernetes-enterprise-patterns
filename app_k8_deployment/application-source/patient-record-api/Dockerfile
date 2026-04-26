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
# CONFIGURATION EXPLANATION `python:3.12.8-slim` is the base image, meaning the operating-system layer plus
# Python runtime the API will run on. Pinning the version makes builds reproducible and lets security scanners
# report vulnerabilities against a known artifact.
FROM python:3.12.8-slim

# ENTERPRISE EMPHASIS: Keep the runtime directory explicit. This makes image
# scanning, debugging, and shell inspection easier for platform teams.
# CONFIGURATION EXPLANATION `/opt/patient-record-api` is the application working directory inside the image.
# Keeping app files in one predictable path makes debugging, file permissions, and container image reviews easier.
WORKDIR /opt/patient-record-api

# ENTERPRISE EMPHASIS: Install dependencies before copying application code so
# Docker can reuse the dependency layer when only business code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt

COPY app ./app

# ENTERPRISE EMPHASIS: Application containers should not run as root. The
# Kubernetes Deployment also enforces this with a pod securityContext so the
# image and runtime policy agree.
# CONFIGURATION EXPLANATION UID and GID `10001` create a non-root Linux user for the API process. Non-root
# containers reduce the damage possible if application code is exploited, and the Kubernetes Deployment uses
# the same UID so image and pod security policy agree.
RUN groupadd --system --gid 10001 patientapi \
    && useradd --system --uid 10001 --gid patientapi --home-dir /opt/patient-record-api patientapi \
    && chown -R patientapi:patientapi /opt/patient-record-api

# CONFIGURATION EXPLANATION `PYTHONUNBUFFERED=1` sends Python logs directly to stdout/stderr. Kubernetes log
# collection expects container processes to write there so operators can read logs with `kubectl logs`.
ENV PYTHONUNBUFFERED=1
# CONFIGURATION EXPLANATION `API_HOST=0.0.0.0` means listen on the pod network interface, not only inside the
# container. A Kubernetes Service can only reach the API if the process accepts traffic on the pod IP.
ENV API_HOST=0.0.0.0
# CONFIGURATION EXPLANATION `API_PORT=8080` must match the Dockerfile EXPOSE, Uvicorn command, Deployment
# containerPort, and backend Service targetPort so traffic reaches the FastAPI process.
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
# CONFIGURATION EXPLANATION `EXPOSE 8080` is image metadata documenting the API listener port. It does not publish
# the port by itself; Kubernetes still needs the Deployment containerPort and Service targetPort to match.
EXPOSE 8080

# CONFIGURATION EXPLANATION `USER patientapi` switches the process away from root before the server starts. This
# aligns with the Deployment securityContext and is a baseline enterprise container hardening practice.
USER patientapi

# CONFIGURATION EXPLANATION The Uvicorn command starts the FastAPI app factory on host `0.0.0.0` and port `8080`.
# Those values are part of the runtime contract with Kubernetes probes and Services.
CMD ["python", "-m", "uvicorn", "app.main:create_application", "--factory", "--host", "0.0.0.0", "--port", "8080"]
