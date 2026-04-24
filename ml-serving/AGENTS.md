# ml-serving/AGENTS.md — Local Instructions for the ML Model Serving Track
#
# =============================================================================
# DEFER TO ROOT FIRST
# =============================================================================
# All global rules live in the root AGENTS.md.
# Read the root AGENTS.md COMPLETELY before reading this file.
# This file ONLY adds specializations that apply inside ml-serving/.
# It does NOT duplicate or override any root rules.
# =============================================================================

## Scope

This file governs agent behavior inside the `ml-serving/` directory only.

`ml-serving/` is the model serving track. It assumes the learner has completed
all of `setup/` and understands Kubernetes fundamentals. The track teaches how
enterprise ML platforms deploy, version, scale, and operate inference services
on top of Kubernetes.

---

## Local Additions for ml-serving/

### Track Prerequisites Rule

When writing content in `ml-serving/`, assume the learner knows:
- Namespace isolation
- Pod lifecycle and restarts
- Deployments, ReplicaSets, rollouts
- Services (ClusterIP and NodePort at minimum)
- ConfigMaps and Secrets
- RBAC at the namespace level
- Resource requests and limits
- Health probes

If a concept from `setup/` is needed, reference it with a link — do not
re-explain it. If a concept is NEW to `ml-serving/`, explain it fully.

### KServe-First Rule

The primary learning path in `ml-serving/` is KServe-based. When adding
new serving examples, use KServe patterns first. Custom application serving
(FastAPI, Flask, custom containers) belongs in `05-custom-fastapi-serving/`
and must be framed as a contrast study — not as the preferred default.

**Why KServe first?**
Enterprise ML platforms (SageMaker endpoints, Vertex AI, Azure ML Online
Endpoints) all share the same abstraction that KServe provides: a unified
InferenceService resource that handles scaling, routing, and model versioning
without the team owning a custom server implementation.

### Folder Separation Rule

Code for a custom serving container image lives in a folder suffixed with
`-runtime-image/` or `custom-*-runtime/`. Kubernetes manifests that deploy
that image live in a separate folder suffixed with `-k8s/` or `*-manifests/`.
Never mix container image source code with Kubernetes deployment manifests.

### Model Lifecycle Annotations Rule

Every YAML that references a model must include comments explaining:
- Where the model artifact lives (local path, S3, GCS, Azure Blob)
- How the model is versioned (name + version tag convention)
- What the enterprise model registry equivalent would be
  (MLflow, SageMaker Model Registry, Vertex AI Model Registry)
- What happens when a new model version is deployed (rolling update? canary?)

### GPU Annotation Rule

This repository's machine has an RTX 2060 (6 GB VRAM). When GPU-related
resources appear (nvidia.com/gpu resource limits, GPU node selectors,
CUDA-aware container images), include:
- A note that this is for the RTX 2060 local setup
- The enterprise equivalent (A100, H100, on EKS with GPU node groups)
- What driver version is required and how to verify it in WSL2

### Enterprise Platforms to Reference

In this track, enterprise translations should reference at minimum:
- **AWS SageMaker** (MLOps platform most common in enterprise)
- **Google Vertex AI** (most common for large-scale ML)
- **Azure Machine Learning** (enterprise Microsoft-stack shops)
- **Databricks / MLflow** (common in data-intensive enterprises)
