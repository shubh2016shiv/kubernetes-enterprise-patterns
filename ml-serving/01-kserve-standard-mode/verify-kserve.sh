#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/01-kserve-standard-mode/verify-kserve.sh
#
# PURPOSE:
#   Verify that the KServe control plane is alive before deploying a model.
#
# WHAT TO LOOK FOR:
#   - kserve namespace exists
#   - controller manager pod is Running/Ready
#   - inferenceservices.serving.kserve.io CRD exists
# =============================================================================

set -euo pipefail

echo "==> KServe namespace"
kubectl get namespace kserve

echo "==> KServe pods"
kubectl get pods -n kserve -o wide

echo "==> KServe CRDs"
kubectl get crd | grep serving.kserve.io

echo "==> Deployment mode configured in controller ConfigMap"
# This shows the cluster-wide default. Individual InferenceServices can still
# override it with the annotation:
#   serving.kserve.io/deploymentMode: Standard
kubectl get configmap inferenceservice-config -n kserve -o yaml | grep -A8 "deploy:" || true

