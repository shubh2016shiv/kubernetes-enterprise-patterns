# 08-resource-management

## What is this?
This module teaches Kubernetes resource management: the controls that prevent one workload or team from consuming unfair amounts of CPU, memory, storage, or API objects. In `07-rbac/`, we controlled who can do what. This module controls how much an authorized workload is allowed to consume after it is admitted into the namespace.

## Why does this exist?
Enterprise Kubernetes clusters are shared platforms. A team can have the correct RBAC permission to deploy, but still accidentally harm the cluster by deploying too many replicas, omitting resource requests, or setting memory limits far beyond what the nodes can support. ResourceQuota protects the namespace as a whole. LimitRange protects individual pods and containers. Together, they reduce noisy-neighbor incidents and make capacity planning possible.

## ASCII concept diagram

```text
APPLICATIONS NAMESPACE

  Platform guardrails
  -------------------

  ResourceQuota: applications-quota
    Namespace budget:
      requests.cpu:    2 cores
      requests.memory: 2 Gi
      limits.cpu:      4 cores
      limits.memory:   4 Gi
      pods:            20

          |
          | caps total namespace usage
          v

  LimitRange: applications-limit-range
    Per-container defaults:
      request: 100m CPU, 128Mi memory
      limit:   500m CPU, 256Mi memory

    Per-container max:
      1 CPU, 512Mi memory

          |
          | injects defaults and rejects out-of-bounds containers
          v

  Deployment: resource-managed-gateway
    replicas: 2
    each pod requests 100m CPU and 128Mi memory
    each pod limits   250m CPU and 256Mi memory

  Key lesson:
    RBAC says whether you may deploy.
    Resource management says how much you may consume.
```

## Learning steps

1. Read [resource-quota.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/08-resource-management/resource-quota.yaml) to understand the namespace-level budget for CPU, memory, object counts, and storage claims.
2. Read [limit-range.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/08-resource-management/limit-range.yaml) to understand per-container defaults, minimums, and maximums.
3. Read [deployment-with-limits.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/08-resource-management/deployment-with-limits.yaml) to see a compliant Deployment with explicit requests and limits.
4. Run [commands.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/08-resource-management/commands.sh) to apply the policies, deploy the workload, inspect quota usage, and test a rejected oversized pod with server-side dry-run.
5. Compare this module with `07-rbac/`: RBAC grants permission to submit work, while ResourceQuota and LimitRange decide whether the submitted work fits the namespace policy.
6. Move next to `09-health-checks/`, because once workloads have fair resource boundaries, the next production concern is teaching Kubernetes how to detect healthy and unhealthy containers.

## Commands

Run the walkthrough from the repository root in WSL2:

```bash
bash setup/08-resource-management/commands.sh
```

What you should see on the happy path:

```text
=== Stage 1.0: Preflight Checks ===
applications namespace exists

=== Stage 2.0: Apply Resource Policies ===
resourcequota/applications-quota created
limitrange/applications-limit-range created

=== Stage 3.0: Deploy Compliant Workload ===
deployment.apps/resource-managed-gateway created
deployment "resource-managed-gateway" successfully rolled out

=== Stage 4.0: Inspect Quota Usage ===
Name:            applications-quota
Resource         Used    Hard
requests.cpu     ...     2
requests.memory  ...     2Gi

=== Stage 5.0: Prove LimitRange Rejection ===
Error from server (Forbidden): ...
```

Useful manual commands:

```bash
kubectl describe quota applications-quota -n applications
kubectl describe limitrange applications-limit-range -n applications
kubectl get deployment resource-managed-gateway -n applications
kubectl get pods -n applications -l app=resource-managed-gateway -o wide
kubectl describe pod -n applications -l app=resource-managed-gateway
kubectl top pods -n applications
kubectl delete -f setup/08-resource-management/deployment-with-limits.yaml
```

If older notes still reference the previous entrypoint, it now delegates to the canonical runner:

```bash
bash setup/08-resource-management/resource-commands.sh
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Set a small ResourceQuota on `applications` | Team or environment quotas on EKS, GKE, and AKS | Shared clusters need predictable capacity and fair tenant boundaries. |
| Use LimitRange defaults and max values | Admission policies, namespace templates, and platform baselines | Enterprises reject workloads that omit resources or exceed approved sizes. |
| Manually apply resource policy YAML | Argo CD, Flux, Terraform, or platform APIs | Resource policy changes affect tenant capacity and usually require review. |
| Use hand-picked requests and limits | VPA recommendations, Prometheus data, and load tests | Production teams tune resource values from real usage instead of guesses. |
| Inspect quota with `kubectl describe quota` | Kubecost, OpenCost, Grafana, and cloud billing reports | Enterprise platforms use resource data for chargeback, showback, and capacity planning. |
| Use a laptop kind cluster with conservative limits | Managed node groups, autoscaling node pools, or Karpenter | Cloud clusters can add nodes, but quotas still protect budgets and blast radius. |

## What to check if something goes wrong

1. Workload is rejected with `exceeded quota`:
Run `kubectl describe quota applications-quota -n applications`. The `Used` column shows which resource is exhausted.

2. Workload is rejected by LimitRange:
Run `kubectl describe limitrange applications-limit-range -n applications`. Check whether the container request or limit is below the minimum or above the maximum.

3. Pod is Pending:
Run `kubectl describe pod <pod-name> -n applications`. If the namespace quota accepted the pod but the node cannot fit it, the scheduler events usually show `Insufficient cpu` or `Insufficient memory`.

4. Pod is OOMKilled:
Run `kubectl describe pod <pod-name> -n applications` and inspect the last state. Memory limits are enforced by killing the container when it exceeds the limit.

5. CPU seems slow but the pod is not killed:
CPU limits throttle containers instead of killing them. Use `kubectl top pod` when metrics-server is available, or inspect application latency.

6. Quota usage looks higher than expected:
Old ReplicaSets, completed pods, or other modules may still be using namespace resources. Run `kubectl get all -n applications` and clean up resources you no longer need.

## Happy path: how to read the output

1. ResourceQuota is created:
The namespace now has a hard tenant budget.

2. LimitRange is created:
The namespace now has per-container defaults and boundaries.

3. Deployment rolls out:
The workload fits inside both the namespace quota and per-container bounds.

4. Quota usage increases:
Requests and limits from the Deployment now count against the namespace budget.

5. Oversized dry-run pod is rejected:
This is a successful safety test. The platform policy is blocking a workload that would be too large for this namespace.

6. The module points to health checks next:
Resource policy controls how much a workload can consume; probes teach Kubernetes when the workload is actually healthy.
