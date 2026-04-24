#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/03-wine-quality-inferenceservice/02-inspect-generated-k8s-objects.sh
#
# PURPOSE:
#   Show what KServe generated after you applied the InferenceService.
#
# WHY THIS MATTERS:
#   Interview-level Kubernetes understanding comes from seeing the controller
#   pattern:
#
#     You create high-level desired state:
#       InferenceService/wine-quality
#
#     Controller creates lower-level desired state:
#       Deployment, Service, HPA, Pods, ReplicaSet, networking resources
#
#     Kubelet/container runtime creates actual running containers.
# =============================================================================

set -euo pipefail

NS="ml-serving"
NAME="wine-quality"

echo "==> High-level KServe object"
kubectl get inferenceservice "${NAME}" -n "${NS}" -o wide

echo
echo "==> Full KServe status"
# The status section is where KServe tells you whether the model is ready,
# what URL was assigned, and what condition failed if it is not ready.
kubectl describe inferenceservice "${NAME}" -n "${NS}"

echo
echo "==> Generated Deployments"
kubectl get deployment -n "${NS}" -l serving.kserve.io/inferenceservice="${NAME}" -o wide

echo
echo "==> Generated Pods"
kubectl get pods -n "${NS}" -l serving.kserve.io/inferenceservice="${NAME}" -o wide

echo
echo "==> Generated Services"
kubectl get service -n "${NS}" -l serving.kserve.io/inferenceservice="${NAME}" -o wide

echo
echo "==> Generated HPA"
kubectl get hpa -n "${NS}" || true

echo
echo "==> Recent events"
kubectl get events -n "${NS}" --sort-by=.lastTimestamp | tail -20

