# 10-enterprise-patterns

## What is this?
This module teaches the Kubernetes patterns that turn individual working applications into production-ready platform workloads. Earlier modules taught the primitives one by one: Deployments keep pods alive, Services route traffic, ConfigMaps and Secrets inject runtime data, RBAC controls permissions, ResourceQuota controls consumption, and probes detect health. Enterprise patterns combine those primitives into safer defaults for real shared clusters.

The patterns in this module are:

```text
NetworkPolicy           controls which pods may talk to which other pods
PodDisruptionBudget     protects replicas during planned maintenance
HorizontalPodAutoscaler changes replica count when load changes
Scheduling constraints  influence where pods land across nodes
```

## Why does this exist?
Production clusters fail in boring, repeatable ways. A compromised pod talks to systems it should never reach. A node upgrade evicts too many replicas at once. Traffic spikes faster than humans can scale a Deployment. A scheduler places all replicas on one worker node and a single node failure becomes an outage. Enterprise patterns reduce those risks before an incident happens.

This module does not assume you already know enterprise vocabulary. Read the words below as plain English:

```text
Zero trust:
  Do not assume a pod is safe just because it is inside the cluster.
  Allow only the traffic the application truly needs.

Disruption:
  A planned event that moves or stops pods, such as node drain, node upgrade,
  cluster autoscaler scale-down, or maintenance.

Autoscaling:
  Letting Kubernetes change replica count based on measurements such as CPU.

Scheduling:
  The Kubernetes decision of choosing which node should run a pod.

Affinity:
  A preference or rule that attracts pods toward certain nodes or away/toward
  other pods.

Taint:
  A marker on a node that repels pods unless those pods explicitly tolerate it.

Toleration:
  A pod-side permission saying "I am allowed to run on nodes with this taint."
```

## ASCII concept diagram

```text
ENTERPRISE PROTECTION LAYERS AROUND THE LEARNING APP

  Client / debug pod
        |
        | allowed ingress to gateway
        v
  inference-gateway Service
        |
        v
  inference-gateway pods
        |
        | allowed egress only to DNS and risk-profile-api pods
        v
  risk-profile-api Service
        |
        v
  risk-profile-api pods

  NetworkPolicy:
    "Only the known traffic paths above are allowed."

  PodDisruptionBudget:
    "During voluntary maintenance, keep at least 2 gateway pods available."

  HorizontalPodAutoscaler:
    "Keep 3 gateway pods normally; scale toward 6 if CPU stays high."

  Scheduling constraints:
    "Prefer spreading replicas across worker nodes so one node is not a single
     point of failure."

  Key lesson:
    Enterprise Kubernetes is not one magic feature.
    It is many small safety contracts layered around ordinary workloads.
```

## Learning steps

1. Read [network-policy.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/10-enterprise-patterns/network-policy.yaml) to understand default-deny networking, DNS exceptions, gateway ingress, and gateway-to-backend traffic.
2. Read [pod-disruption-budget.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/10-enterprise-patterns/pod-disruption-budget.yaml) to understand voluntary disruptions and why at least 2 gateway replicas should stay available during maintenance.
3. Read [horizontal-pod-autoscaler.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/10-enterprise-patterns/horizontal-pod-autoscaler.yaml) to understand CPU-based replica scaling and why metrics-server matters.
4. Read [scheduling-constraints-demo.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/10-enterprise-patterns/scheduling-constraints-demo.yaml) to understand topology spread, node affinity, and tolerations without needing a real cloud node pool.
5. Run [commands.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/10-enterprise-patterns/commands.sh) to apply the base gateway/backend workloads, Services, and enterprise controls, then inspect each control.
6. After this module, pause before adding more production features. Your earlier black-box pod instinct is correct: the fundamentals track should add an observability/debugging module covering logs, Events, metrics, tracing, and centralized log platforms.

## Commands

Run the walkthrough from the repository root in WSL2:

```bash
bash setup/10-enterprise-patterns/commands.sh
```

What you should see on the happy path:

```text
=== Stage 1.0: Preflight Checks ===
applications namespace exists

=== Stage 2.0: Ensure Base Application Exists ===
deployment.apps/risk-profile-api-deployment configured
deployment.apps/inference-gateway-deployment configured
service/risk-profile-api-clusterip configured
service/inference-gateway-clusterip configured

=== Stage 3.0: Apply Enterprise Policies ===
networkpolicy.networking.k8s.io/default-deny-applications created
networkpolicy.networking.k8s.io/allow-dns-egress created
networkpolicy.networking.k8s.io/allow-gateway-ingress created
networkpolicy.networking.k8s.io/allow-gateway-to-risk-api created
poddisruptionbudget.policy/inference-gateway-pdb created
horizontalpodautoscaler.autoscaling/inference-gateway-hpa created
deployment.apps/scheduling-constraints-demo created

=== Stage 4.0: Inspect Protection State ===
...
```

Useful manual commands:

```bash
kubectl get networkpolicy -n applications
kubectl describe networkpolicy allow-gateway-to-risk-api -n applications
kubectl get pdb inference-gateway-pdb -n applications
kubectl describe pdb inference-gateway-pdb -n applications
kubectl get hpa inference-gateway-hpa -n applications
kubectl describe hpa inference-gateway-hpa -n applications
kubectl get pods -n applications -l app=inference-gateway -o wide
kubectl get pods -n applications -l app=scheduling-constraints-demo -o wide
kubectl describe pod -n applications -l app=scheduling-constraints-demo
```

If older notes still reference the previous entrypoint, it now delegates to the canonical runner:

```bash
bash setup/10-enterprise-patterns/enterprise-commands.sh
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Apply NetworkPolicy YAML in kind | Enforce zero-trust networking with Calico, Cilium, or cloud CNI policy support on EKS, GKE, and AKS | NetworkPolicy only works when the CNI plugin enforces it. kind's default networking may not enforce policies. |
| Allow gateway-to-backend traffic by labels | Build service-to-service allowlists by app labels, namespaces, and sometimes service mesh identity | Labels make policy portable across changing pod IPs. Mesh identity adds stronger workload authentication. |
| Use one PDB for the gateway | Require PDBs for every highly available service | PDBs protect availability during node drains, upgrades, and autoscaler scale-down. |
| Use CPU-based HPA | Scale on CPU, memory, Prometheus metrics, queue depth, or KEDA event sources | CPU is easy to teach, but real bottlenecks may be requests per second, Kafka lag, SQS depth, or GPU queue length. |
| Demonstrate scheduling constraints on kind nodes | Spread across availability zones, instance types, GPU pools, and dedicated node groups | Enterprise schedulers protect against node, rack, zone, and capacity-class failures. |
| Use tolerations as a safe example | Taints reserve nodes for special workloads such as GPU, security, ingress, or data workloads | Taints protect expensive or sensitive nodes from accidental general-purpose scheduling. |

## What to check if something goes wrong

1. NetworkPolicy seems to do nothing:
Check the CNI plugin. NetworkPolicy is an API object, but enforcement belongs to the CNI. kind's default CNI may accept the YAML without enforcing it.

2. DNS stops working after default deny:
Run `kubectl exec <pod> -n applications -- nslookup kubernetes.default`. If DNS fails, inspect `allow-dns-egress`.

3. Gateway cannot call backend:
Check labels first. Run `kubectl get pods -n applications --show-labels` and confirm gateway pods have `app=inference-gateway` and backend pods have `app=risk-profile-api`.

4. PDB shows `ALLOWED DISRUPTIONS` as `0`:
That may be correct if not enough replicas are Ready. Check `kubectl get pods -n applications -l app=inference-gateway`.

5. HPA shows `<unknown>`:
metrics-server is missing or unhealthy. HPA needs metrics to calculate CPU utilization.

6. Scheduling demo pods stay Pending:
Run `kubectl describe pod <pod-name> -n applications`. The Events section tells you whether topology spread, affinity, taints, or resource availability blocked scheduling.

7. Tolerations do not appear to change anything:
That is expected unless a node actually has a matching taint. This module teaches the syntax safely without tainting your local kind nodes.

## Happy path: how to read the output

1. NetworkPolicies are created:
The namespace now has an explicit network intent. Even if local kind does not enforce it, the production manifest is visible and reviewable.

2. PDB is created:
Kubernetes now knows not to voluntarily evict too many gateway pods at once.

3. HPA is created:
Kubernetes now has a rule for adjusting gateway replicas from 3 to 6 when CPU is high.

4. Scheduling demo rolls out:
You can inspect how topology spread, affinity, and tolerations are represented in a pod spec.

5. The inspection commands explain current state:
Enterprise operations is mostly reading state, understanding contracts, and knowing which controller owns each decision.

6. The fundamentals track is now ready for a new observability/debugging module:
Enterprise patterns protect the platform. Observability explains what is happening when those protections still are not enough.
