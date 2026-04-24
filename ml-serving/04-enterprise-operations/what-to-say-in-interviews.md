# What To Say In Interviews

## One-Minute Explanation

I deploy trained ML models on Kubernetes using KServe. The trained artifact is
stored outside the container image in an artifact store such as S3, GCS, Azure
Blob, MLflow, or a PVC for local learning. The deployment contract is an
`InferenceService` YAML. KServe watches that custom resource and creates the
underlying Kubernetes resources such as Deployment, Service, and HPA in Standard
mode. This keeps model serving standardized across teams and separates model
versions from application/container versions.

## Why This Is Enterprise-Ready

- The model artifact is immutable and versioned.
- The serving runtime is standardized.
- Kubernetes resource requests and limits are declared.
- Autoscaling is controlled by KServe and Kubernetes HPA/KEDA.
- Rollout and rollback happen through YAML/GitOps rather than manual server work.
- Operations are observable through `kubectl describe`, generated pods, logs,
  service status, and autoscaler state.

## Local Versus Production

Local:

```text
model.joblib -> PVC -> KServe InferenceService -> local predictor pod
```

Production:

```text
training pipeline -> S3/GCS/Blob/MLflow -> KServe InferenceService -> node pool
```

The Kubernetes object stays conceptually the same. Only the `storageUri`,
credentials, networking, and scaling policy become more production-grade.

