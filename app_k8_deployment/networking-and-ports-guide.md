# Kubernetes Networking and Port Mapping Guide

## What is this?

This note explains how the patient intake UI, nginx, Kubernetes Services, and FastAPI backend talk to each other. The current lab uses port `8080` in several places for simplicity, but those `8080` values do not all live in one container. Each pod has its own network space, so multiple containers can safely listen on the same port number.

## Why does this exist?

In enterprise Kubernetes, teams rarely rely on memory for ports. They trace the traffic path: browser port, Service port, Service `targetPort`, container port, and application listen port. The rule is not "every component must use the same port." The real rule is: each hop must point to the next correct listener.

## Current Lab: Same Container Port Pattern

```text
Learner browser
  http://localhost:30001
        |
        | NodePort exposed by frontend Service
        v
patient-intake-ui-service
  nodePort: 30001
  port: 8080
  targetPort: http
        |
        | targetPort "http" means frontend pod containerPort named "http"
        v
patient-intake-ui pod
  nginx listens on 8080
        |
        | Browser submits /api/patients
        | nginx proxy_pass http://patient-record-api-service:8080/
        v
patient-record-api-service
  port: 8080
  targetPort: http
        |
        | targetPort "http" means backend pod containerPort named "http"
        v
patient-record-api pod
  Uvicorn/FastAPI listens on 0.0.0.0:8080
```

In this lab, both nginx and FastAPI listen on `8080`, but they are in different pods:

```text
frontend pod network space                 backend pod network space
nginx: 0.0.0.0:8080                        uvicorn: 0.0.0.0:8080
```

There is no conflict because each pod has its own IP address and network namespace.

## Service Is Not The App

This distinction matters:

```text
Deployment = tells Kubernetes how many pods to run and how to update them
Pod        = runs the real container process
Service    = stable network doorway in front of matching pods
```

So these names do not mean the same thing:

```text
patient-intake-ui Deployment
  creates patient-intake-ui pods
  each pod runs an nginx container
  nginx serves index.html, CSS, and JavaScript

patient-intake-ui-service
  does not run the UI
  does not contain index.html
  does not execute nginx
  only forwards traffic to pods with matching labels
```

The frontend Service exists because your browser needs a stable way to reach the
frontend pods:

```text
Browser
  -> patient-intake-ui-service
  -> patient-intake-ui pod
  -> nginx container
  -> index.html / JavaScript / CSS
```

The backend Service exists for the same reason, but its caller is different:

```text
nginx container
  -> patient-record-api-service
  -> patient-record-api pod
  -> FastAPI / Uvicorn process
```

The main difference is exposure:

| Service | Type | Who calls it? | Why |
|---|---|---|---|
| `patient-intake-ui-service` | `NodePort` | Your laptop browser | The UI is the lab entry point, so it must be reachable from outside the cluster. |
| `patient-record-api-service` | `ClusterIP` | nginx inside the cluster | The backend should stay private and only receive traffic through the frontend path. |

When a Kubernetes manifest says "frontend Service," read it as "the stable
network doorway to the frontend pods," not "the frontend application itself."

## If The Ports Are Different

The ports can be different as long as each Kubernetes object points to the correct next hop.

Example design:

```text
Browser uses localhost:30001
Frontend Service exposes port 80
Frontend nginx listens on 8080
Backend Service exposes port 9000
Backend FastAPI listens on 7000
```

End-to-end flow:

```text
Learner browser
  http://localhost:30001
        |
        v
frontend Service
  nodePort: 30001       <- laptop entry point
  port: 80              <- in-cluster Service port
  targetPort: 8080      <- frontend container listener
        |
        v
frontend pod
  nginx listen 8080
  proxy_pass http://patient-record-api-service:9000/
        |
        v
backend Service
  port: 9000            <- address nginx calls
  targetPort: 7000      <- backend container listener
        |
        v
backend pod
  uvicorn --host 0.0.0.0 --port 7000
```

The backend still works because nginx calls the backend Service on the Service port:

```nginx
proxy_pass http://patient-record-api-service:9000/;
```

The backend Service then forwards to the backend container port:

```yaml
ports:
  - name: http
    port: 9000
    targetPort: 7000
```

And the backend app must actually listen on that target port:

```dockerfile
CMD ["python", "-m", "uvicorn", "app.main:create_application", "--factory", "--host", "0.0.0.0", "--port", "7000"]
```

## The Matching Rules

### Frontend path

```text
frontend Service targetPort
  must match
nginx listen port inside the frontend container
```

If the frontend Service says:

```yaml
targetPort: 8080
```

then `nginx.conf` must say:

```nginx
listen 8080;
```

### Backend path

```text
backend Service port
  must match
the port nginx calls in proxy_pass
```

If nginx says:

```nginx
proxy_pass http://patient-record-api-service:9000/;
```

then the backend Service must expose:

```yaml
port: 9000
```

And:

```text
backend Service targetPort
  must match
FastAPI/Uvicorn listen port inside the backend container
```

If the backend Service says:

```yaml
targetPort: 7000
```

then Uvicorn must start with:

```text
--host 0.0.0.0 --port 7000
```

## Port Vocabulary

| Field | Where it lives | What it means |
|---|---|---|
| `nodePort` | Service | Port opened on each Kubernetes node for access from outside the cluster. Used locally so the laptop browser can reach the UI. |
| `port` | Service | Stable in-cluster port that other pods call through Service DNS. |
| `targetPort` | Service | Destination port on the selected pods. Can be a number or a named container port like `http`. |
| `containerPort` | Deployment pod spec | Documentation for the port the container is expected to listen on. Named ports let Services use readable names. |
| `listen` | nginx.conf | The real port nginx opens inside the frontend container. |
| `--port` | Uvicorn command | The real port FastAPI opens inside the backend container. |
| `EXPOSE` | Dockerfile | Image metadata for humans and tools. It does not publish the port by itself. |

## Enterprise Translation

| Local lab | Enterprise equivalent | Why it differs |
|---|---|---|
| Browser reaches `localhost:30001` through NodePort | Browser reaches DNS name through Ingress, API Gateway, or cloud load balancer | Enterprises need TLS, DNS, WAF, audit logging, and centralized traffic policy. |
| nginx proxies `/api/*` to `patient-record-api-service:8080` | Frontend or gateway calls an internal Service DNS name, sometimes through service mesh | Service DNS remains the stable backend identity even when pods roll or scale. |
| Backend Service is `ClusterIP` | Internal API Service is usually private, often protected by NetworkPolicy and mTLS | Backends should not be directly exposed unless they are public APIs. |
| Ports are written directly in YAML | Ports may come from Helm values, Kustomize overlays, or platform templates | Different environments may use different conventions while preserving the same traffic chain. |

## What To Remember

Do not memorize that everything must be `8080`. Memorize the chain.

```text
Caller port -> Service port -> Service targetPort -> container app listen port
```

Same port numbers are convenient for learning. Different port numbers are normal in real systems. The system works when every hop points to the next correct hop.
