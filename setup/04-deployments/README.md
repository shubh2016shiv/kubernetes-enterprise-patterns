# 04-deployments

## What is this?
A Deployment is the standard Kubernetes controller for long-running stateless workloads. In real clusters, you almost never have just one Deployment. You have many sibling Deployments, each owning its own pods, replica count, rollout strategy, and revision history.

## Why does this exist?
Enterprise platforms need a safe way to keep applications alive while code changes, nodes fail, and pods restart. Deployments give that control plane behavior. They answer: how many copies should exist, how should updates happen, and how do we roll back? They do **not** answer stable networking between applications. That second part belongs to Services, which is why this module flows directly into `05-services/`.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES CLUSTER                                 │
│                                                                             │
│  Deployment A: inference-gateway-deployment                                │
│     └── ReplicaSet A                                                       │
│         ├── gateway pod 1                                                  │
│         ├── gateway pod 2                                                  │
│         └── gateway pod 3                                                  │
│                                                                             │
│  Deployment B: risk-profile-api-deployment                                 │
│     └── ReplicaSet B                                                       │
│         ├── backend pod 1                                                  │
│         └── backend pod 2                                                  │
│                                                                             │
│  Important boundary:                                                       │
│    Deployments own pod lifecycle.                                          │
│    They do NOT create stable pod-to-pod discovery by themselves.           │
│                                                                             │
│  Next module adds Services:                                                │
│    gateway Service DNS -> gateway pods                                     │
│    risk-profile-api Service DNS -> backend pods                            │
│    gateway pod -> calls backend Service DNS name                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Learning steps

1. Read [risk-profile-api-deployment.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/04-deployments/risk-profile-api-deployment.yaml) first so you can see a backend Deployment that exists independently from the gateway.
2. Read [inference-gateway-deployment.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/04-deployments/inference-gateway-deployment.yaml) and focus on `replicas`, `selector`, `strategy`, `topologySpreadConstraints`, and the `RISK_PROFILE_API_BASE_URL` comment that points forward to Services.
3. Run [rolling-update.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/04-deployments/rolling-update.sh) to create both Deployments, update only the gateway, inspect history, and scale the gateway.
4. Run [observe-lifecycle.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/04-deployments/observe-lifecycle.sh) to see what happens when pods restart, roll, reschedule, and scale.
5. Run [rollback.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/04-deployments/rollback.sh) when you want to isolate the rollback path and see that one Deployment can roll back while its sibling stays untouched.
6. Move next to `05-services/` because that is the module where these sibling Deployments become a stable application graph instead of two isolated sets of pods.

## What `risk-profile-api-deployment.yaml` means in enterprise terms

[risk-profile-api-deployment.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/04-deployments/risk-profile-api-deployment.yaml) means:

```text
This is an internal backend application.
Keep 2 pod replicas running.
If one pod dies, replace it.
If we deploy a new version, roll it safely.
```

That maps directly to real enterprise Deployments such as:

```text
pricing-api-deployment
fraud-risk-api-deployment
feature-flag-api-deployment
customer-profile-api-deployment
model-metadata-api-deployment
```

The exact business name changes from company to company, but the Kubernetes contract stays the same:

```text
Deployment
  owns pod lifecycle
  owns replica count
  owns rollout strategy
  owns rollback history
```

## Commands

Run the main walkthrough:

```bash
bash setup/04-deployments/rolling-update.sh
```

What you should see on the happy path:

```text
=== Stage 1.0: Deploy Sibling Workloads ===
deployment.apps/risk-profile-api-deployment created
deployment.apps/inference-gateway-deployment created
deployment "risk-profile-api-deployment" successfully rolled out
deployment "inference-gateway-deployment" successfully rolled out

=== Stage 2.0: Perform Rolling Update ===
deployment.apps/inference-gateway-deployment image updated
deployment "inference-gateway-deployment" successfully rolled out

=== Stage 3.0: Inspect Rollout History ===
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

Run the lifecycle observation drill:

```bash
bash setup/04-deployments/observe-lifecycle.sh
```

What you should see:

```text
=== Stage 2.0: Pod Restart / Replacement ===
pod "<old-gateway-pod>" deleted
pod/<new-gateway-pod> condition met

=== Stage 3.0: Rolling Restart ===
deployment.apps/inference-gateway-deployment restarted
deployment "inference-gateway-deployment" successfully rolled out

=== Stage 4.0: Reschedule Drill ===
node/<node-name> cordoned
pod "<pod-name>" deleted
node/<node-name> uncordoned

=== Stage 5.0: Scale Drill ===
deployment.apps/inference-gateway-deployment scaled
```

Run the rollback-only walkthrough:

```bash
bash setup/04-deployments/rollback.sh
```

What you should see:

```text
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
deployment.apps/inference-gateway-deployment rolled back
deployment "inference-gateway-deployment" successfully rolled out
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
risk-profile-api-deployment   2/2     2            2           ...
```

Useful manual commands after the script:

```bash
kubectl get deployments -n applications
kubectl get rs -n applications -l app=inference-gateway
kubectl get rs -n applications -l app=risk-profile-api
kubectl get pods -n applications -l tier=backend -o wide
kubectl describe deployment inference-gateway-deployment -n applications
kubectl describe deployment risk-profile-api-deployment -n applications
kubectl rollout history deployment/inference-gateway-deployment -n applications
kubectl rollout undo deployment/inference-gateway-deployment -n applications
kubectl rollout restart deployment/inference-gateway-deployment -n applications
kubectl scale deployment/inference-gateway-deployment --replicas=5 -n applications
kubectl describe pod <pod-name> -n applications
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Two plain Deployments in one namespace | Many Deployments per namespace, often split by domain or tier | Real platforms run dozens or hundreds of Deployments, but the ownership model stays the same. |
| Manual `kubectl set image` on one Deployment | GitOps PR updates a specific Deployment manifest | Production teams want audit trails, approval, and drift detection. |
| Gateway and backend in one learner namespace | Separate namespaces, environments, and policy boundaries | Enterprises add stronger isolation, RBAC, policy, and promotion workflows. |
| One laptop cluster | EKS managed node groups, GKE node pools, or AKS agent pools | Same Deployment controller behavior, different infrastructure scale and reliability guarantees. |
| Simple Python demo images | Signed internal OCI images with vulnerability scanning | Production packaging goes through CI, provenance, and security controls. |

## What to check if something goes wrong

1. One Deployment is healthy but the other is not:
Run `kubectl get deployments -n applications` first. Remember that each Deployment reconciles independently. A bad gateway rollout does not automatically imply the backend Deployment is broken.

2. Rollout is stuck on the gateway:
Run `kubectl get rs -n applications -l app=inference-gateway` and `kubectl get pods -n applications -l app=inference-gateway`. Usually the new ReplicaSet exists but new pods are not reaching `Ready`, so Kubernetes will not continue deleting old pods.

3. Deleted pod came back immediately:
That is healthy Deployment behavior. You deleted actual state, but the ReplicaSet reconciled it back to desired state.

4. Replacement pod landed on the same node:
That can happen after a plain pod delete. Kubernetes schedules based on current constraints and available capacity. To force a true reschedule demo, the lifecycle script temporarily cordons one node.

5. You expected the two Deployments to talk already:
That expectation belongs to the next module. A Deployment creates pods. A Service creates stable discovery. Until Services exist, any direct pod-to-pod communication would be fragile because pod IPs change.

6. New pods never schedule:
Check `kubectl describe pod <pending-pod> -n applications`. On a small learner cluster, spread constraints and resource requests can expose `Insufficient cpu` or `Insufficient memory`.

7. Rollback did not help:
Inspect rollout history and ReplicaSets. Rollback only restores an earlier pod template for that Deployment. It does not automatically revert sibling Deployments, ConfigMaps, Secrets, or database changes.

## Happy path: how to read the output

1. Two `deployment.apps/... created` lines:
The cluster accepted two separate desired-state controllers. That is closer to how real application stacks look in production.

2. `kubectl get deployments` shows both gateway and backend:
This means you now have two independent controllers, each with its own replica count and health.

3. Only the gateway gets a second ReplicaSet during the update:
That is the key lesson. Rollouts happen per Deployment, not per namespace and not per "application" in the abstract.

4. Rollback restores only the gateway:
Again, this is expected. Kubernetes lets you recover one bad service without disturbing other healthy sibling services.

5. The gateway YAML mentions a backend Service DNS name, but calls may still fail in this module:
That is also expected. The Deployment is prepared for networking, but stable resolution arrives in `05-services/`.

6. During lifecycle drills, the important thing is not memorizing pod names:
Pod names are supposed to change. The production skill is watching the chain: Deployment desired state -> ReplicaSet ownership -> pod readiness -> node placement -> Events.
