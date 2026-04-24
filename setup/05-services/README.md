# 05-services

## What is a Service?
A Service is an abstract way to expose an application running on a set of Pods as a network service. Because Pod IPs change every time a Pod restarts or is recreated by a Deployment, you cannot rely on them. A Service gives your deployment a stable IP address and a stable DNS name, and acts as a load balancer across all healthy Pods.

## Why does this exist?
In an enterprise environment, applications are highly dynamic. Pods scale up, scale down, crash, and move between nodes. Without Services, components (like a frontend talking to a backend API) would constantly lose connection to each other as IPs change.

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                  KUBERNETES CLUSTER                        │
│                                                            │
│                  ┌──────────────────┐                      │
│   DNS Lookup ───►│      CoreDNS     │                      │
│ (nginx-clusterip)└─────────┬────────┘                      │
│                            │ (Returns 10.96.x.x)           │
│                            ▼                               │
│                  ┌──────────────────┐                      │
│   Traffic ──────►│     SERVICE      │                      │
│                  │ (Stable IP/DNS)  │                      │
│                  └─────────┬────────┘                      │
│                            │                               │
│              Endpoints (Auto-updated via Selectors)        │
│          ┌─────────────────┼─────────────────┐             │
│          ▼                 ▼                 ▼             │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐      │
│   │ Pod (IP A)  │   │ Pod (IP B)  │   │ Pod (IP C)  │      │
│   │ (Ready)     │   │ (Ready)     │   │ (Not Ready) │      │
│   └─────────────┘   └─────────────┘   └─────────────┘      │
│     Gets traffic      Gets traffic      Ignored            │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Internal Routing**: Review `clusterip-service.yaml`. This is the default and most common service type. It exposes the service on a cluster-internal IP.
2. **External Access**: Review `nodeport-service.yaml`. This opens a specific port on every Node's IP. It is used here for local testing.
3. **Apply and Inspect**: Run `service-commands.sh` to see how Endpoints are wired to Services, and how DNS resolution works.

## Commands

### 1. Apply and Test Services
```bash
bash setup/05-services/service-commands.sh
```

**What you should see**:
```
=== Step 1: Applying Services ===
service/nginx-clusterip created
service/nginx-nodeport created

=== Step 3: Endpoints — Where Traffic Actually Goes ===
NAME              ENDPOINTS                                      AGE
nginx-clusterip   10.244.1.5:80,10.244.2.4:80,10.244.2.5:80      5s
...
```

### 2. Manual Testing
The `nodeport-service` exposes port 30000 to your local machine (thanks to our `kind` port mapping in Phase 1).

Open your browser to: `http://localhost:30000`

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| NodePort Service | LoadBalancer Service + Ingress/Gateway API | NodePorts are insecure and hard to manage (port conflicts). Enterprises use cloud load balancers (AWS ALB) or Ingress Controllers for external traffic. |
| Basic `ClusterIP` | Service Mesh (Istio / Linkerd) | A standard ClusterIP does raw L4 TCP load balancing. Service meshes provide L7 (HTTP) routing, retries, circuit breaking, and mutual TLS encryption. |
| Flat DNS | Cross-cluster DNS | In massive enterprises, services might need to discover other services residing in entirely different physical clusters. |

## What to Check If Something Goes Wrong

1. **Service exists but connection refused**: The Service's `selector` does not match the Pod labels. Run `kubectl get endpoints <service-name> -n applications`. If it says `<none>`, the labels don't match.
2. **Endpoints exist but traffic times out**: Check if the `targetPort` in your Service YAML matches the `containerPort` in your Pod YAML.
3. **Pods are running but endpoints is empty**: The Pods might be failing their `readinessProbe`. Only *Ready* pods are added to the Endpoints list. Run `kubectl get pods -n applications` and check the `READY` column.
