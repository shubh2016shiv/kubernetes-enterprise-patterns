#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/01-kserve-standard-mode/install-kserve-standard-mode.sh
#
# PURPOSE:
#   Install KServe in Standard mode for local enterprise-style model serving.
#
# WHY STANDARD MODE:
#   KServe's default mode is Knative. Knative is excellent for scale-to-zero and
#   request-driven autoscaling, but it adds more moving parts for a learner:
#   Knative Serving, activator, queue-proxy behavior, and often Istio/Gateway
#   concerns.
#
#   Standard mode is the right first enterprise mental model:
#     InferenceService -> Deployment + Service + Ingress/Gateway + HPA
#
#   That means after you apply one KServe YAML, you can inspect normal
#   Kubernetes objects and understand what the controller generated.
#
# REQUIREMENTS:
#   - The cluster from `setup/01-cluster-setup/` is running.
#   - kubectl is configured against that cluster context.
#   - helm is installed.
#   - metrics-server is recommended if you want HPA metrics to work locally.
#
# REFERENCE:
#   https://kserve.github.io/website/docs/admin-guide/kubernetes-deployment
# =============================================================================

set -euo pipefail

KSERVE_VERSION="v0.17.0"

echo "==> Checking cluster access"
kubectl cluster-info
echo "==> Current kubectl context"
kubectl config current-context

echo "==> Installing KServe CRDs"
# CRD = CustomResourceDefinition.
# This teaches Kubernetes a new resource kind named `InferenceService`.
# Without the CRD, `kubectl apply -f wine-quality-sklearn-isvc.yaml` would fail
# because Kubernetes would not know what `kind: InferenceService` means.
helm upgrade --install kserve-crd \
  oci://ghcr.io/kserve/charts/kserve-crd \
  --version "${KSERVE_VERSION}" \
  --namespace kserve \
  --create-namespace

echo "==> Installing KServe controller resources in Standard mode"
# The controller watches InferenceService objects and reconciles desired state.
# `deploymentMode=Standard` tells KServe to generate ordinary Kubernetes
# Deployments and Services instead of Knative Services.
helm upgrade --install kserve \
  oci://ghcr.io/kserve/charts/kserve-resources \
  --version "${KSERVE_VERSION}" \
  --namespace kserve \
  --create-namespace \
  --set kserve.controller.deploymentMode=Standard

echo "==> Waiting for KServe controller pods"
kubectl wait --for=condition=Ready pod \
  --selector=control-plane=kserve-controller-manager \
  --namespace kserve \
  --timeout=180s

echo "==> KServe installed"
kubectl get pods -n kserve
kubectl get crd | grep serving.kserve.io || true
