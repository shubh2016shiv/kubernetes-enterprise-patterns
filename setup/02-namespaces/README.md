# 02-namespaces

## What is a Namespace?
A namespace is a logical boundary inside one Kubernetes cluster. It provides a scope for names and helps organize resources. It is not a separate physical or virtual machine. 

## Why does this exist?
In an enterprise environment, a single cluster often hosts hundreds of applications, monitoring stacks, and security tools. Without namespaces, everything dumps into `default`, leading to naming collisions, unclear ownership, and the inability to apply targeted access controls (RBAC) or resource quotas.

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                      │
│                                                            │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────────┐  │
│  │ NS: default     │ │ NS: kube-system │ │ NS: security │  │
│  │ (Avoid using)   │ │ (Control Plane) │ │ (Vault, etc) │  │
│  └─────────────────┘ └─────────────────┘ └──────────────┘  │
│                                                            │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────────┐  │
│  │ NS: applications│ │ NS: monitoring  │ │ NS: staging  │  │
│  │ (Your Apps)     │ │ (Prometheus)    │ │ (Testing)    │  │
│  └─────────────────┘ └─────────────────┘ └──────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Understand the Topology**: Review [namespaces.yaml](namespaces.yaml) to see how enterprise labels and annotations are structured.
2. **Apply the Structure**: Run the application script.
3. **Inspect**: Verify the cluster state and labels.

## Commands

### 1. Apply the Namespaces
```bash
bash setup/02-namespaces/apply-namespaces.sh
```

**What you should see**:
```
✓ Namespaces applied!
[1] Applying namespace definitions...
namespace/applications created
namespace/monitoring created
namespace/security created
namespace/ingress-system created
namespace/staging created
```

### 2. Verify and Inspect
```bash
kubectl get namespaces
```

**What you should see**:
```
NAME               STATUS   AGE
applications       Active   10s
default            Active   5m
ingress-system     Active   10s
...
```

```bash
kubectl describe namespace applications
```

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Single file definition | Terraform / GitOps (ArgoCD) | Enterprises enforce namespace creation via automation (IaC) to guarantee labels exist |
| Simulate environments (`staging`, `prod`) | Separate physical clusters | Blast-radius isolation. True production is physically separated from staging. |
| Manual context switching | `kubectx` / `kubens` / DevContainers | Speed and safety to prevent deploying to the wrong environment |

## What to Check If Something Goes Wrong

1. **"Error from server (Forbidden)"**: You don't have RBAC permission to list or create namespaces. In a real enterprise, creating namespaces is highly restricted. Locally, your `kind` admin context has full rights. Ensure you ran `export KUBECONFIG=~/.kube/config` (or the kind-specific config).
2. **Resources end up in `default`**: You ran `kubectl apply -f pod.yaml` without specifying `-n applications` AND without setting a default context namespace. Always use explicit `-n`.
