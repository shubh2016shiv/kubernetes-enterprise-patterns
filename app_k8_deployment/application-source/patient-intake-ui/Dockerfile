# =============================================================================
# FILE:    Dockerfile
# PURPOSE: Build the patient-intake-ui image that serves the browser form.
# USAGE:   docker build -t patient-intake-ui:1.0.0 .
# WHEN:    app_k8_deployment - before loading the image into the kind cluster.
# PREREQS: Docker Desktop is running with WSL2 integration enabled.
# OUTPUT:  A static UI image served by nginx.
# =============================================================================

# ENTERPRISE EMPHASIS: Pin nginx instead of using `latest`. Frontend images are
# still production artifacts and must be scanned, versioned, and promoted.
FROM nginx:1.27.3-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

# EXPOSE: Document which port this container is expected to serve.
# This should match the `listen 8080;` directive in nginx.conf.
#
# Why: EXPOSE does not start nginx or publish the port by itself. It is metadata
# for humans and tooling. The actual listener is nginx.conf, and Kubernetes sends
# Service traffic to the container port that nginx is listening on.
#
# If nginx.conf says `listen 8080;` but this Dockerfile says `EXPOSE 80`, the app
# may still run, but the image becomes misleading and future Kubernetes manifests
# may point to the wrong port. In enterprise teams, these values are kept aligned
# so Dockerfiles, runtime configs, and Kubernetes manifests tell the same story.
EXPOSE 8080
