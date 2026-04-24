# 08-resource-management

## What is Resource Management?
Resource management in Kubernetes is how a platform team ensures that compute resources (CPU, Memory, Storage) are shared fairly and safely among multiple applications in a cluster.
- **ResourceQuota**: Sets a hard limit on the *total* resources a namespace can consume.
- **LimitRange**: Sets default limits and requests for *individual* pods, and enforces minimum/maximum sizes.

## Why does this exist?
In an enterprise environment, clusters are "multi-tenant" (shared by many teams). Without ResourceQuotas, one team deploying a buggy application with a memory leak could consume 100% of the cluster's memory, causing every other team's applications to crash (the "noisy neighbor" problem).

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                    CLUSTER NAMESPACE                       │
│                                                            │
│                  ┌──────────────────┐                      │
│                  │  ResourceQuota   │                      │
│                  │  Max CPU: 10     │                      │
│                  │  Max Mem: 20Gi   │                      │
│                  └────────┬─────────┘                      │
│                           │ Enforces total ceiling         │
│                           ▼                                │
│                  ┌──────────────────┐                      │
│                  │    LimitRange    │                      │
│                  │  Default CPU: 1  │                      │
│                  │  Max CPU/Pod: 4  │                      │
│                  └────────┬─────────┘                      │
│                           │ Injects defaults / Checks bounds
│                           ▼                                │
│      ┌────────────────┐        ┌────────────────┐          │
│      │ Pod A (2 CPU)  │        │ Pod B (No CPU) │          │
│      └────────────────┘        └────────────────┘          │
│      (Allowed: Total=2)        (Assigned Default=1)        │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Namespace Ceiling**: Review `resource-quota.yaml`. This acts as a budget for the namespace.
2. **Pod Boundaries**: Review `limit-range.yaml`. This acts as a safety net if a developer forgets to set resources.
3. **Application Spec**: Review `deployment-with-limits.yaml`. Notice how the `resources` block specifies `requests` (what it needs to schedule) and `limits` (the maximum it can use before getting throttled or killed).
4. **Apply and Test**: Run `resource-commands.sh` to see these policies applied to the `applications` namespace.

## Commands

### 1. Apply and Verify Resources
```bash
bash setup/08-resource-management/resource-commands.sh
```

**What you should see**:
```
=== Stage 1: Apply Resource Policies ===
resourcequota/app-namespace-quota created
limitrange/app-limit-range created

=== Stage 3: Inspect Quota Usage ===
Name:            app-namespace-quota
Namespace:       applications
Resource         Used    Hard
--------         ----    ----
limits.cpu       500m    4
limits.memory    256Mi   4Gi
requests.cpu     100m    2
requests.memory  128Mi   2Gi
...
```

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Manual YAML application | GitOps + Admission Controllers (Kyverno / OPA) | Enterprises use policy engines to completely *reject* any deployment that doesn't explicitly state its resource requests, enforcing best practices. |
| Static quotas | FinOps tools (Kubecost) | Platform teams track quota usage vs request vs actual consumption to bill individual teams for their cluster usage (chargeback). |
| Basic Requests/Limits | Vertical Pod Autoscaler (VPA) | Developers are notoriously bad at guessing how much CPU/Memory they need. VPA monitors actual usage and automatically adjusts the requests/limits over time. |

## What to Check If Something Goes Wrong

1. **`Forbidden: exceeded quota`**: You tried to deploy a pod that requests more CPU/Memory than the `ResourceQuota` has left available. Check `kubectl describe quota -n applications` to see what is exhausted.
2. **`Forbidden: maximum cpu usage per Container is...`**: You tried to deploy a pod that asks for more CPU than the `LimitRange` allows for a single pod.
3. **Pod is `OOMKilled` (Out of Memory)**: The pod tried to use more memory than its `limit` specified in the Deployment YAML. Kubernetes strictly terminates containers that exceed their memory limit.
