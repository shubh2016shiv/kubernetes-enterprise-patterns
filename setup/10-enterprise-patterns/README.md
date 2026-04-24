# 10-enterprise-patterns

## What are Enterprise Patterns?
These are the advanced Kubernetes controls that elevate a cluster from a "toy" environment to a production-ready, highly available, and secure platform.
- **NetworkPolicy**: The "firewall" of Kubernetes. Implements zero-trust networking between pods.
- **PodDisruptionBudget (PDB)**: Protects your application from being accidentally taken offline during cluster maintenance (node upgrades).
- **HorizontalPodAutoscaler (HPA)**: Automatically adds or removes Pods based on CPU/Memory usage.

## Why do they exist?
In an enterprise environment:
1. **Security**: By default, any pod in Kubernetes can talk to any other pod. NetworkPolicies lock this down so a compromised frontend cannot directly access the database.
2. **Reliability**: When the platform team upgrades Kubernetes nodes, they drain the nodes. Without a PDB, the platform team might accidentally drain all replicas of your app simultaneously, causing an outage.
3. **Cost & Scale**: Traffic is unpredictable. HPA ensures you have enough pods during a spike, and scales down to save cloud costs when traffic drops.

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                    ENTERPRISE CONTROLS                     │
│                                                            │
│  ┌─────────────────┐             ┌─────────────────┐       │
│  │ NetworkPolicy   │             │       HPA       │       │
│  │ (Blocks Traffic)│             │ (Scales Pods)   │       │
│  └───────┬─────────┘             └─────────┬───────┘       │
│          │                                 │               │
│          ▼                                 ▼               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                     DEPLOYMENT                       │  │
│  │                                                      │  │
│  │ ┌─────────┐   ┌─────────┐   ┌─────────┐              │  │
│  │ │ Pod 1   │   │ Pod 2   │   │ Pod 3   │ (Added by HPA│  │
│  │ └─────────┘   └─────────┘   └─────────┘  during spike)  │  │
│  └──────────────────────────────────────────────────────┘  │
│                             ▲                              │
│                             │                              │
│  ┌──────────────────────────┴───────────────────────────┐  │
│  │               PodDisruptionBudget (PDB)              │  │
│  │    "Always keep at least 2 pods running during node  │  │
│  │                 upgrades/maintenance"                │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Zero-Trust Networking**: Review `network-policy.yaml`. Notice how it explicitly selects pods and defines ingress/egress rules based on labels.
2. **Availability Protection**: Review `pod-disruption-budget.yaml`. It requires `minAvailable: 2`. K8s will block node maintenance if it would violate this rule.
3. **Autoscaling**: Review `horizontal-pod-autoscaler.yaml`. It sets a target CPU utilization (e.g., 80%).
4. **Apply**: Run `enterprise-commands.sh` to apply these policies.

## Commands

### 1. Apply Enterprise Policies
```bash
bash setup/10-enterprise-patterns/enterprise-commands.sh
```

**What you should see**:
```
=== Stage 1: Apply Enterprise Patterns ===
networkpolicy.networking.k8s.io/default-deny-all created
networkpolicy.networking.k8s.io/allow-frontend-to-backend created
poddisruptionbudget.policy/nginx-pdb created
horizontalpodautoscaler.autoscaling/nginx-hpa created
...
```

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Basic `NetworkPolicy` | Cilium / Calico | `kind` comes with a basic CNI. Enterprises use advanced CNIs like Cilium (eBPF) for L7 network policies (blocking specific HTTP paths, not just ports). |
| Standard HPA (CPU/Memory) | KEDA (Kubernetes Event-driven Autoscaling) | CPU isn't always the best scaling metric. Enterprises use KEDA to scale based on Kafka queue length, Prometheus metrics, or AWS SQS depth. |
| PDBs on standard Deployments | Topology Aware Routing | Advanced enterprises combine PDBs with Topology Constraints to ensure the surviving pods during maintenance are spread across different availability zones. |

## What to Check If Something Goes Wrong

1. **"Connection Refused" / Timeouts**: You applied a NetworkPolicy that is too restrictive. By default, a "deny-all" policy stops *everything*, including DNS resolution, unless explicitly allowed.
2. **HPA shows `<unknown>` for CPU**: Your cluster does not have the `metrics-server` installed. HPA requires this component to read CPU usage from pods.
3. **Cannot delete a Node (Eviction Error)**: Your PDB is too strict (e.g., `minAvailable: 100%`). The platform cannot drain the node because the PDB refuses to let a pod die.
