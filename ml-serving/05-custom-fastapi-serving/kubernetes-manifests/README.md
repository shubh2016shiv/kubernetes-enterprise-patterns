# kubernetes-manifests

This folder contains the Kubernetes resources for the custom FastAPI serving path.

## File Order

1. `01-application-config.yaml`: runtime configuration injected by the platform.
2. `02-inference-deployment.yaml`: the application pods and rollout behavior.
3. `03-service-and-hpa.yaml`: networking and scaling.
4. `apply-stack.sh`: applies the stack in sequence.
5. `test-inference.sh`: sends a request to the running service.

## What This Teaches

This folder shows exactly what KServe saves you from managing by hand: image rollout, service wiring, probe design, autoscaling, and request entrypoints.
