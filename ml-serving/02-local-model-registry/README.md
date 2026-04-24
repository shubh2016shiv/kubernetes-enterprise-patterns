# 02-local-model-registry

This module creates a local stand-in for an enterprise model artifact store.

## File Order

1. `01-namespace.yaml`: isolation boundary for model artifacts.
2. `02-model-store-pvc.yaml`: persistent storage for model files.
3. `03-model-store-loader-pod.yaml`: helper pod for loading artifacts.
4. `load-model-into-pvc.sh`: operational script that copies artifacts into the PVC-backed store.

## Enterprise Translation

In production this would usually be S3, GCS, Azure Blob, MLflow artifacts, or an OCI-backed registry. The PVC here is a learning stand-in for the storage contract, not a claim that PVCs are the universal enterprise answer.
