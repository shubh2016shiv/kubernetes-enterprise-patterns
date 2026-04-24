# Enterprise ML Serving With KServe
#
# This folder is intentionally OUTSIDE `setup/`.
#
# `setup/` teaches Kubernetes primitives: Pods, Deployments, Services, RBAC,
# probes, quotas, and network policy.
#
# `ml-serving/` teaches what happens AFTER the data science team has trained a
# model and handed platform/MLOps a versioned artifact. In enterprise MLOps,
# serving is not "run a Python file on a server"; serving is an orchestration
# contract between:
#
#   1. Model registry / artifact store
#      - Enterprise: S3, GCS, Azure Blob, MLflow artifact store, OCI registry
#      - Local demo: Kubernetes PVC that behaves like a tiny local model store
#
#   2. Serving control plane
#      - KServe watches `InferenceService` YAML and creates lower-level
#        Kubernetes objects for you.
#
#   3. Runtime container
#      - KServe sklearn runtime loads `model.joblib` and exposes Open Inference
#        Protocol endpoints.
#
#   4. Kubernetes scheduler and autoscaler
#      - The cluster decides where the inference pods run and when to scale.
#
# Why KServe instead of a hand-written Deployment?
#
#   A normal Deployment is useful when you own every detail of the web server.
#   KServe is useful when the enterprise wants a standard model-serving platform:
#
#     - common CRD: `InferenceService`
#     - common model storage contract: `storageUri`
#     - common runtimes: sklearn, xgboost, tensorflow, pytorch, huggingface, etc.
#     - common autoscaling hooks
#     - common traffic and status model
#
# The custom FastAPI example is kept as a contrast study in:
#
#   - `05-custom-fastapi-serving/runtime-image/`
#   - `05-custom-fastapi-serving/kubernetes-manifests/`
#
# The professional platform-first path starts with KServe. Study the custom
# FastAPI path after you understand what KServe gives you automatically.

## Learning Order

```text
ml-serving/
├── 00-local-platform/
│   ├── README.md
│   └── docker-desktop-kubernetes.md
├── 01-kserve-standard-mode/
│   ├── README.md
│   ├── install-kserve-standard-mode.sh
│   └── verify-kserve.sh
├── 02-local-model-registry/
│   ├── README.md
│   ├── 01-namespace.yaml
│   ├── 02-model-store-pvc.yaml
│   ├── 03-model-store-loader-pod.yaml
│   └── load-model-into-pvc.sh
├── 03-wine-quality-inferenceservice/
│   ├── README.md
│   ├── 01-wine-quality-sklearn-isvc.yaml
│   ├── 02-inspect-generated-k8s-objects.sh
│   ├── 03-test-open-inference-v2.sh
│   └── sample-v2-infer.json
├── 04-enterprise-operations/
│   ├── README.md
│   ├── rollout-and-debug.sh
│   └── what-to-say-in-interviews.md
└── 05-custom-fastapi-serving/
    ├── README.md
    ├── runtime-image/
    │   ├── README.md
    │   ├── Dockerfile
    │   ├── build-and-load.sh
    │   ├── requirements.txt
    │   ├── app/
    │   └── model/
    └── kubernetes-manifests/
        ├── README.md
        ├── 01-application-config.yaml
        ├── 02-inference-deployment.yaml
        ├── 03-service-and-hpa.yaml
        ├── apply-stack.sh
        └── test-inference.sh
```

## The Mental Model

```text
You apply YAML
    |
    v
KServe controller sees InferenceService
    |
    v
KServe creates Deployment + Service + HPA + networking objects
    |
    v
Storage initializer / PVC mount provides model.joblib
    |
    v
sklearn runtime loads model into memory
    |
    v
clients call /v2/models/<model-name>/infer
```

## Primary References Used While Building This

- KServe Kubernetes/Standard deployment guide:
  https://kserve.github.io/website/docs/admin-guide/kubernetes-deployment
- KServe PVC model storage:
  https://kserve.github.io/website/docs/model-serving/storage/providers/pvc
- KServe storage overview:
  https://kserve.github.io/website/docs/model-serving/storage/overview
- KServe HPA autoscaling in Standard mode:
  https://kserve.github.io/website/docs/model-serving/predictive-inference/autoscaling/hpa-autoscaler
- Docker Desktop Kubernetes:
  https://docs.docker.com/desktop/use-desktop/kubernetes/
