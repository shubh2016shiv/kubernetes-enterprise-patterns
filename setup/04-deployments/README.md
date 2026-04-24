# 04-deployments

## What is a Deployment?
A Deployment is a Kubernetes controller that manages stateless applications. It ensures that a specified number of Pod replicas are running at any given time. If a node fails and its Pods die, the Deployment creates new ones. It also handles rolling updates to new versions without downtime.

## Why does this exist?
In an enterprise environment, you **never** run bare Pods for long-running services. If a bare Pod dies, it is gone forever. Deployments provide the self-healing and lifecycle management required for production workloads. 

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                  DEPLOYMENT CONTROLLER                     │
│               Manages rollout history & strategy           │
│                           │                                │
│                           ▼                                │
│                  REPLICASET CONTROLLER                     │
│             Manages the exact number of Pods               │
│             (Tied to a specific image version)             │
│                           │                                │
│         ┌─────────────────┼─────────────────┐              │
│         ▼                 ▼                 ▼              │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐        │
│  │    Pod     │    │    Pod     │    │    Pod     │        │
│  │ (v1.25.4)  │    │ (v1.25.4)  │    │ (v1.25.4)  │        │
│  └────────────┘    └────────────┘    └────────────┘        │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Read the Spec**: Open `nginx-deployment.yaml`. Pay close attention to:
    - The `replicas` count.
    - The `selector` and how it matches the Pod template labels.
    - The `strategy` (RollingUpdate).
    - The `readinessProbe` and `livenessProbe` (critical for zero-downtime rollouts).
2. **Apply and Rollout**: Run the `rolling-update.sh` script to see a deployment happen and update in real-time.
3. **Rollback**: Run the `rollback.sh` script to see how quickly you can revert a bad release.

## Commands

### 1. Perform a Rolling Update
```bash
bash setup/04-deployments/rolling-update.sh
```

**What you should see**:
```
=== 1. Create Initial Deployment ===
deployment.apps/nginx-deployment created
Waiting for deployment "nginx-deployment" rollout to finish: 0 of 3 updated replicas are available...
...
=== 2. Trigger Rolling Update (Change Image Version) ===
deployment.apps/nginx-deployment image updated
...
```

### 2. Perform a Rollback
```bash
bash setup/04-deployments/rollback.sh
```

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| `kubectl apply` and `kubectl set image` | GitOps (ArgoCD/Flux) | Humans do not run deployment commands. They merge code, and a CD tool applies the change automatically. |
| Basic `RollingUpdate` | Canary or Blue/Green (Argo Rollouts / Flagger) | RollingUpdates replace pods blindly. Advanced deployments shift 10% of traffic, run metrics checks, and automatically rollback if error rates spike. |
| Hardcoded `replicas: 3` | Horizontal Pod Autoscaler (HPA) | Traffic fluctuates. HPA scales the deployment automatically based on CPU/Memory or custom metrics. |

## What to Check If Something Goes Wrong

1. **Deployment is created but no Pods appear**: Your `selector.matchLabels` in the Deployment do not match the `labels` in the Pod template. Kubernetes won't create pods it can't manage.
2. **Rollout is stuck**: Run `kubectl describe deployment nginx-deployment -n applications`. Often, a readiness probe is failing on the new pods, so the deployment pauses to prevent taking down the healthy old pods.
3. **Old pods won't die**: Similar to above. If new pods don't pass readiness checks, Kubernetes will not kill the old ones (because `maxUnavailable` is protecting your capacity).
