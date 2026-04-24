# 07-rbac

## What is RBAC?
RBAC (Role-Based Access Control) is how Kubernetes determines *who* can do *what* inside the cluster.
- **ServiceAccount**: The "who" (Identity for Pods).
- **Role / ClusterRole**: The "what" (A set of permissions, e.g., "can read pods").
- **RoleBinding / ClusterRoleBinding**: The link that grants the Role to the ServiceAccount.

## Why does this exist?
In an enterprise environment, security is paramount. By default, applications running in Kubernetes shouldn't be able to query the Kubernetes API to see other applications' secrets, delete namespaces, or scale deployments. RBAC implements the principle of least privilege.

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                    KUBERNETES RBAC                         │
│                                                            │
│                  ┌──────────────────┐                      │
│                  │  RoleBinding     │                      │
│                  │ (The connection) │                      │
│                  └───────┬───┬──────┘                      │
│                 Binds    │   │    Grants                   │
│                 ┌────────┘   └────────┐                    │
│                 ▼                     ▼                    │
│      ┌──────────────────┐      ┌──────────────────┐        │
│      │  ServiceAccount  │      │       Role       │        │
│      │    (The WHO)     │      │    (The WHAT)    │        │
│      └────────┬─────────┘      └──────────────────┘        │
│               │                  - API: "pods"             │
│               │                  - Verbs: "get", "list"    │
│               ▼                                            │
│      ┌──────────────────┐                                  │
│      │       Pod        │                                  │
│      │ (App using SA)   │                                  │
│      └──────────────────┘                                  │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Identity**: Review `service-account.yaml`. This is the identity your application pods will assume.
2. **Permissions**: Review `role.yaml` and `clusterrole.yaml`. Notice the difference between namespace-scoped and cluster-scoped permissions.
3. **The Link**: Review `rolebinding.yaml`. This ties the ServiceAccount to the Role.
4. **Apply and Test**: Run the `rbac-commands.sh` script to verify RBAC enforcement.

## Commands

### 1. Apply and Verify RBAC
```bash
bash setup/07-rbac/rbac-commands.sh
```

**What you should see**:
```
=== Stage 1: Apply RBAC Objects ===
serviceaccount/ml-api-sa created
role.rbac.authorization.k8s.io/ml-api-reader created
rolebinding.rbac.authorization.k8s.io/ml-api-reader-binding created

=== Stage 2: Test Permissions (`auth can-i`) ===
Can ml-api-sa GET pods in applications?
yes
Can ml-api-sa DELETE pods in applications?
no
```

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Local Service Accounts | IRSA (AWS) / Workload Identity (GKE) | In the cloud, Kubernetes ServiceAccounts are mapped directly to Cloud IAM Roles (AWS IAM). This allows Pods to access S3/DynamoDB securely without passwords. |
| Broad `list` permissions | Fine-grained ResourceNames | We often give "list pods" locally. Enterprises restrict to specific resource names where possible to limit blast radius. |
| Manual RoleBindings | OIDC Group Mapping | For human users, enterprises map Corporate AD/Okta groups to ClusterRoles, they don't create individual ServiceAccounts for developers. |

## What to Check If Something Goes Wrong

1. **"Forbidden" Errors**: Your pod is trying to do something not explicitly listed in its Role. Run `kubectl describe role <role-name> -n applications` and check the rules.
2. **Default ServiceAccount**: If you don't specify `serviceAccountName` in your Pod/Deployment YAML, it uses the `default` service account, which has almost zero permissions.
3. **ClusterRole vs Role**: You cannot bind a `Role` (namespace-bound) to a resource that is cluster-scoped (like Nodes or PersistentVolumes). For those, you must use a `ClusterRole` and `ClusterRoleBinding`.
