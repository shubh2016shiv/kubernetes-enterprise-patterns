# 05-services

## What is this?
A Service is the Kubernetes abstraction that gives a changing set of pods one stable network identity. In this module, Services do two jobs at once: they expose the gateway Deployment to clients and they let the gateway Deployment call a sibling backend Deployment reliably.

## Why does this exist?
In enterprise platforms, workloads are constantly moving. Pods restart, roll, reschedule, and scale. If one Deployment tried to call another by raw pod IP, it would break during normal cluster life. Services solve that by creating stable DNS names and stable virtual IPs. This is the practical answer to the learner question: "How do multiple Deployments talk to each other in Kubernetes?"

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES CLUSTER                                 │
│                                                                             │
│  Client pod or laptop                                                      │
│        │                                                                    │
│        │ 1. call gateway Service                                            │
│        ▼                                                                    │
│  inference-gateway Service                                                  │
│        │                                                                    │
│        ▼                                                                    │
│  gateway pod                                                                │
│        │                                                                    │
│        │ 2. call sibling backend by Service DNS                             │
│        ▼                                                                    │
│  risk-profile-api Service                                                   │
│        │                                                                    │
│        ▼                                                                    │
│  backend pod A / backend pod B                                              │
│                                                                             │
│  Key lesson:                                                                │
│    Deployment -> owns pod lifecycle                                         │
│    Service    -> owns stable discovery and traffic routing                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Learning steps

1. Read [risk-profile-api-clusterip.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/05-services/risk-profile-api-clusterip.yaml) first. It is the internal Service that answers the question "how does one Deployment reach another?"
2. Read [clusterip-service.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/05-services/clusterip-service.yaml) to understand the gateway's internal stable identity.
3. Read [nodeport-service.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/05-services/nodeport-service.yaml) to understand the local external-access shortcut.
4. Run [commands.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/05-services/commands.sh) to apply the Services, inspect endpoints, test DNS resolution, and watch gateway-to-backend communication through Service DNS.
5. Compare this module with `04-deployments/`: Deployments create and maintain pods; Services give those pods stable discoverable entry points.
6. Move next to `06-configmaps-secrets/` because once the application graph is stable, the next production concern is separating code from configuration and credentials.

## What `risk-profile-api-clusterip.yaml` means in enterprise terms

[risk-profile-api-clusterip.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/05-services/risk-profile-api-clusterip.yaml) means:

```text
Give the risk-profile-api backend Deployment a stable internal DNS name
so other workloads can call it without knowing pod IPs.
```

In real Kubernetes, one pod should not call another pod by raw IP. Pod IPs are temporary because pods restart, roll, reschedule, and scale. Instead, a gateway or another service calls the backend Service name:

```text
http://risk-profile-api-clusterip/profile/rules
```

Kubernetes then routes that request to one of the ready backend pods behind the Service.

The real enterprise relationship is:

```text
Deployment
  owns pod lifecycle

Service
  owns stable network identity

Gateway pod
  calls backend Service DNS

Backend Service
  routes to ready backend pods
```

## Commands

Run the walkthrough:

```bash
bash setup/05-services/commands.sh
```

What you should see on the happy path:

```text
=== Stage 1.0: Apply Services ===
service/risk-profile-api-clusterip created
service/inference-gateway-clusterip created
service/inference-gateway-nodeport created

=== Stage 3.0: Inspect Endpoints ===
inference-gateway-clusterip  10.x.x.x:8080,10.x.x.x:8080,...
risk-profile-api-clusterip   10.x.x.x:8081,10.x.x.x:8081

=== Stage 5.0: Test Communication Paths ===
... direct backend JSON ...
... gateway dependency_check JSON ...
```

Useful manual commands:

```bash
kubectl get svc -n applications
kubectl get endpoints -n applications
kubectl describe svc inference-gateway-clusterip -n applications
kubectl describe svc risk-profile-api-clusterip -n applications
kubectl exec platform-debug-toolbox -n applications -- nslookup inference-gateway-clusterip
kubectl exec platform-debug-toolbox -n applications -- nslookup risk-profile-api-clusterip
kubectl exec platform-debug-toolbox -n applications -- wget -qO- http://risk-profile-api-clusterip/profile/rules
kubectl exec platform-debug-toolbox -n applications -- wget -qO- http://inference-gateway-clusterip/dependencies
curl http://localhost:30000/dependencies
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Gateway NodePort on `localhost:30000` | AWS ALB / NLB on EKS, GCLB on GKE, Azure Load Balancer / Application Gateway on AKS | Cloud platforms provide managed external entry points with TLS, health checks, DNS, and firewall integration. |
| Gateway calling backend by ClusterIP Service DNS | The same east-west Service pattern, often plus service mesh | Enterprises may add mTLS, retries, timeouts, auth, and traffic policy, but the stable Service identity is still the base. |
| Manual `kubectl` endpoint checks | GitOps plus dashboards and alerts | Operators still inspect Services and endpoints, but often after Prometheus, Grafana, Datadog, or cloud monitoring detects trouble. |
| One namespace with two Services | Many Services across namespaces and environments | Large organizations separate dev, staging, prod, and often split services by team or domain. |

## What to check if something goes wrong

1. Service exists but has no endpoints:
Run `kubectl get endpoints <service-name> -n applications`. If endpoints are empty, the selector does not match pod labels or the pods are not `Ready`.

2. Backend Service works directly but gateway dependency path fails:
That usually means the backend is healthy but the gateway is misconfigured, cannot resolve DNS, or is calling the wrong URL path.

3. DNS resolution fails inside the cluster:
Run `kubectl exec platform-debug-toolbox -n applications -- cat /etc/resolv.conf` and check CoreDNS pods in `kube-system`. Service discovery depends on cluster DNS being healthy.

4. NodePort opens but browser access fails:
Check the kind port mapping and verify the Service exists with `nodePort: 30000`. In cloud environments, this kind of failure is often replaced by load balancer target registration or security group issues.

5. One backend pod is missing from the endpoint list:
That can be correct. Services include only pods that pass readiness. A `Running` pod can still be excluded from traffic if readiness fails.

## Happy path: how to read the output

1. Three `service/... created` lines:
Kubernetes now has stable entry points for the gateway and the backend, plus one local external route into the gateway.

2. `kubectl get endpoints` shows `:8080` for gateway and `:8081` for backend:
That proves the Services are routing to actual ready pods on the real container ports, not to the Deployments themselves.

3. `nslookup` succeeds for both Services:
CoreDNS is healthy, so pods can find each other by Service DNS name.

4. Direct backend call returns JSON:
The backend Deployment, its Service selector, endpoints, and readiness all line up correctly.

5. Gateway `/dependencies` returns a `dependency_check` object:
This is the practical proof that one Deployment is now talking to another through a Service, which is the enterprise pattern you were asking about.
