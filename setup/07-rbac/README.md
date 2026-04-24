# 07-rbac

## What is this?
This module teaches Kubernetes RBAC: Role-Based Access Control. RBAC is the authorization layer that decides whether an authenticated identity can perform an action against a Kubernetes resource. In `06-configmaps-secrets/`, the cluster learned how to store runtime configuration and fake credentials. This module answers the next enterprise question: who is allowed to read that configuration, and who must be blocked from reading Secrets?

## Why does this exist?
Enterprise Kubernetes clusters host many teams, services, automation tools, and platform agents. Without RBAC, any workload or human with API access could accidentally read credentials, delete workloads, or modify production resources. RBAC implements least privilege: grant only the exact verbs an identity needs, in the smallest namespace scope possible, and prove the result with `kubectl auth can-i`.

## ASCII concept diagram

```text
KUBERNETES AUTHORIZATION FLOW

  Subject / identity                 Binding                         Permissions
  ------------------                 -------                         -----------

  ServiceAccount                     RoleBinding                     Role
  inference-gateway-observer-sa --->  gateway-observer-binding --->   gateway-observer
        |                                  |                              |
        |                                  |                              +-- can get/list/watch pods
        |                                  |                              +-- can get/list services
        |                                  |                              +-- can get/list configmaps
        |                                  |
        |                                  +-- grants only inside applications namespace
        |
        +-- cannot get secrets
        +-- cannot delete pods
        +-- cannot modify deployments

  Key lesson:
    Authentication proves who you are.
    RBAC authorization decides what you can do.
```

## Learning steps

1. Read [service-account.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/07-rbac/service-account.yaml) to understand workload identity and why most application pods should not use the namespace `default` ServiceAccount.
2. Read [role.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/07-rbac/role.yaml) to see a namespace-scoped Role that can inspect pods, Services, and ConfigMaps, but cannot read Secrets.
3. Read [rolebinding.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/07-rbac/rolebinding.yaml) to see the link between the ServiceAccount identity and the Role permissions.
4. Read [clusterrole.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/07-rbac/clusterrole.yaml) and [clusterrolebinding.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/07-rbac/clusterrolebinding.yaml) to contrast namespace-scoped application permissions with cluster-scoped platform-tool permissions.
5. Run [commands.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/07-rbac/commands.sh) to apply the RBAC objects and test allowed and denied actions with `kubectl auth can-i`.
6. Move next to `08-resource-management/`, because after controlling who can do what, the next enterprise concern is controlling how much CPU and memory workloads may consume.

## Commands

Run the walkthrough from the repository root in WSL2:

```bash
bash setup/07-rbac/commands.sh
```

What you should see on the happy path:

```text
=== Stage 1.0: Preflight Checks ===
applications namespace exists
monitoring namespace exists

=== Stage 2.0: Apply Namespace-Scoped RBAC ===
serviceaccount/inference-gateway-observer-sa created
role.rbac.authorization.k8s.io/gateway-observer created
rolebinding.rbac.authorization.k8s.io/gateway-observer-binding created

=== Stage 3.0: Test Application ServiceAccount Permissions ===
Can observer get pods? yes
Can observer get configmaps? yes
Can observer get secrets? no
Can observer delete pods? no

=== Stage 4.0: Apply Cluster-Scoped Monitoring RBAC ===
clusterrole.rbac.authorization.k8s.io/prometheus-read-cluster-state created
clusterrolebinding.rbac.authorization.k8s.io/prometheus-scraper-cluster-read created
```

Useful manual commands:

```bash
kubectl get serviceaccount inference-gateway-observer-sa -n applications
kubectl describe role gateway-observer -n applications
kubectl describe rolebinding gateway-observer-binding -n applications
kubectl auth can-i get configmaps --as=system:serviceaccount:applications:inference-gateway-observer-sa -n applications
kubectl auth can-i get secrets --as=system:serviceaccount:applications:inference-gateway-observer-sa -n applications
kubectl describe clusterrole prometheus-read-cluster-state
kubectl describe clusterrolebinding prometheus-scraper-cluster-read
```

If older notes still reference the previous entrypoint, it now delegates to the canonical runner:

```bash
bash setup/07-rbac/rbac-commands.sh
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Create a ServiceAccount for a demo observer | One ServiceAccount per workload or automation component on EKS, GKE, and AKS | Separate identities make audit logs meaningful and reduce blast radius. |
| Bind a namespace Role in `applications` | Team-scoped Roles per namespace, often managed by Argo CD or Flux | Namespace-scoped access is safer than cluster-wide access for application workloads. |
| Deny Secret reads by omission | Strict Secret access reviews, external secret managers, and RBAC guardrails | Kubernetes RBAC is additive; the safest permission is the one never granted. |
| Use `kubectl auth can-i` manually | CI policy checks, admission controls, and audit-log review | Production teams automate evidence that identities have only approved permissions. |
| Give Prometheus a read-only ClusterRole | Platform agents use ClusterRoles for cross-namespace discovery | Monitoring and security tools often need cluster-wide reads, but still should not get write access. |
| Use Kubernetes ServiceAccounts only | EKS IRSA, GKE Workload Identity, or AKS workload identity | Cloud clusters map pod identity to cloud IAM so pods can access cloud services without static keys. |

## What to check if something goes wrong

1. `kubectl auth can-i` returns `no` when you expected `yes`:
Run `kubectl describe role gateway-observer -n applications` and confirm the Role includes the resource and verb. RBAC rules must match the exact API group, resource, and verb.

2. `kubectl auth can-i` returns `yes` for Secrets:
Stop and inspect all RoleBindings and ClusterRoleBindings for that ServiceAccount. Kubernetes RBAC is additive, so another binding may be granting Secret access.

3. RoleBinding exists but permissions still fail:
Check the subject name and namespace. A ServiceAccount subject must match both name and namespace exactly.

4. ClusterRoleBinding fails because the monitoring ServiceAccount does not exist:
Run `bash setup/02-namespaces/apply-namespaces.sh` first. This RBAC module assumes the `monitoring` namespace from the namespace module exists.

5. You expected a Role to grant node access:
Nodes are cluster-scoped resources. A namespace Role cannot grant access to them. Use a ClusterRole and ClusterRoleBinding for cluster-scoped resources.

6. A pod still uses the `default` ServiceAccount:
Check the pod spec for `serviceAccountName`. If it is missing, Kubernetes uses the namespace `default` ServiceAccount, which is usually the wrong identity for enterprise workloads.

## Happy path: how to read the output

1. ServiceAccount is created:
The cluster now has a workload identity separate from the namespace default identity.

2. Role is created:
The allowed verbs are explicit. Notice that Secrets are absent, which means Secret reads are denied.

3. RoleBinding is created:
The identity and permission set are now connected inside the `applications` namespace.

4. `auth can-i get configmaps` returns `yes`:
The observer can inspect non-sensitive runtime configuration from `06-configmaps-secrets/`.

5. `auth can-i get secrets` returns `no`:
That is the most important security lesson in this module. Secrets require separate, intentional access.

6. ClusterRole and ClusterRoleBinding are applied:
This demonstrates why platform tools such as Prometheus need a different pattern from ordinary application workloads.
