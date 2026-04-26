# 03-pods

## What is a Pod?
A Pod is the smallest, atomic, and most basic deployable unit of computing that you can create and manage in Kubernetes. 
A Pod contains one or more containers (like Docker containers), with shared storage and network resources, and a specification for how to run the containers.

## Why does this exist?
In an enterprise environment, you rarely create isolated Pods directly. Instead, you create higher-level controllers (Deployments, StatefulSets, DaemonSets) that manage Pods for you. 
However, you MUST understand Pods because when something breaks, you don't debug a "Deployment" — you debug the underlying failing Pod. Everything in Kubernetes eventually resolves down to a Pod running on a node.

## Architecture

A **sidecar** is a helper container that runs in the same Pod as the main application container.
It is not a separate service and it is not a second copy of the app. It shares the Pod's network
and volumes, so it can support the app closely. In this module, the app writes log lines to a
shared folder and the sidecar reads that folder to stream the logs.

```text
┌────────────────────────────────────────────────────────────┐
│                    NODE (Worker)                           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                     POD                              │  │
│  │                                                      │  │
│  │  ┌───────────────┐               ┌───────────────┐   │  │
│  │  │ Container 1   │               │ Container 2   │   │  │
│  │  │ (App)         │               │ (Sidecar      │   │  │
│  │  │               │               │  helper)      │   │  │
│  │  │ port 8080     │ ◄── Localhost ┤ port 9090     │   │  │
│  │  └───────────────┘               └───────────────┘   │  │
│  │                                                      │  │
│  │  Shared IP: 10.100.1.5 (All containers share this)   │  │
│  │  Shared Storage: /var/log/app (EmptyDir volume)      │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Understand a Minimal Pod**: Review `01-minimal-pod.yaml`. Notice how resource requests and limits are defined. 
2. **Environment Variables**: Review `02-pod-with-env.yaml`. Notice how the `Downward API` exposes cluster info into the container environment.
3. **Multi-Container Pods**: Review `03-multi-container-pod.yaml`. Notice the sidecar pattern: one primary app container does the business work, and one helper container supports it by shipping logs. This is how service meshes such as Istio and Linkerd, and many monitoring agents, attach platform behavior to an app without changing the app code.
4. **Apply and Inspect**: Run the `pod-commands.sh` script to create these pods and learn how to view logs, execute commands inside them, and query their status.

## Commands

### 1. Run the Walkthrough Script
```bash
bash setup/03-pods/pod-commands.sh
```

**What you should see**:
```
=== 1. Apply pod manifests ===
$ kubectl apply -f .../01-minimal-pod.yaml
pod/platform-debug-toolbox created
...
pod/platform-debug-toolbox condition met

=== 2. List and describe ===
NAME                           READY   STATUS    RESTARTS   AGE
inference-with-log-sidecar     2/2     Running   0          5s
...
```

### 2. Manual Commands to Try
The script will suggest some manual commands at the end. Try them!

```bash
# Open an interactive shell inside the minimal pod:
kubectl exec -it platform-debug-toolbox -n applications -- /bin/sh

# Inside the shell, try DNS resolution (CoreDNS in action):
nslookup kubernetes.default.svc.cluster.local
exit
```

## Happy Path: What Your Output Means

If everything is healthy, these are the expected signals and how to read them:

1. `pod/<name> created`:
Your YAML was accepted by the API server and objects were stored in cluster state.

2. `condition met` after `kubectl wait`:
The pod reached `Ready=True`. This means containers started and are passing readiness checks.

3. `kubectl get pods` shows:
`platform-debug-toolbox` as `1/1 Running`,
`inference-worker-config-demo` as `1/1 Running`,
`inference-with-log-sidecar` as `2/2 Running`.
`2/2` is correct for the sidecar pattern because the Pod has two containers: the main app container and the log helper container. Kubernetes counts both because both must be running for the Pod to be fully healthy.

4. `kubectl describe pod platform-debug-toolbox` shows:
`Status: Running`, `Ready: True`, resource requests/limits, node placement, and normal Events:
`Scheduled -> Pulling -> Pulled -> Created -> Started`.
That event chain is the clean startup path.

5. `kubectl logs inference-worker-config-demo` shows env values:
`POD_NAME`, `POD_NAMESPACE`, `NODE_NAME`, `POD_IP`, `MEMORY_LIMIT_BYTES`.
This confirms Downward API and resourceFieldRef are working as expected.

6. `kubectl logs inference-with-log-sidecar -c inference-app` may be empty:
This is normal when no requests have hit the app yet. The app writes access entries only on incoming HTTP calls.

7. `kubectl logs inference-with-log-sidecar -c log-shipper` initially shows:
`waiting for app log file...`
This is also normal before first request. After traffic hits `/health`, the sidecar helper container should emit lines prefixed with `[inference-log]`.

8. `nslookup kubernetes.default.svc.cluster.local` succeeds:
CoreDNS is healthy and in-cluster service discovery is working.

9. JSONPath section should print values:
Expected:
`<pod-ip>`
`<node-name>`
`<pod-name>\t<phase>` lines.
If this fails with a weird `pods ".items[*]..." not found` error, command argument parsing broke. This has been fixed in `pod-commands.sh`.

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Apply raw Pod YAMLs | Use Deployments/StatefulSets | Raw pods do not self-heal. If the node dies, a raw pod is gone forever. Deployments recreate them. |
| Basic sidecars: helper containers in the same Pod as the app | Service meshes such as Istio and Linkerd, or monitoring/logging agents | Enterprise platforms often inject these helper containers automatically so teams get mutual TLS (encrypted service-to-service traffic), tracing, and logging without rewriting every app. |
| Hardcoded environment vars | Externalized config | In production, config comes from Vault, AWS Secrets Manager, ConfigMaps, or GitOps parameter overrides. |

## What to Check If Something Goes Wrong

1. **Pod is stuck in `Pending`**: Your cluster lacks resources (CPU/Memory). Check `kubectl describe pod <name> -n applications` and look at the `Events` section. It will usually say `0/3 nodes are available: 3 Insufficient memory`. Fix: Check Docker Desktop resource allocation (ensure 8GB).
2. **Pod is `CrashLoopBackOff`**: The container started but exited with an error code, and Kubernetes keeps restarting it. Check the logs: `kubectl logs <pod-name> -n applications`.
3. **Pod is `ImagePullBackOff`**: Kubernetes cannot find or download the container image. Check for typos in the `image:` name or verify network connectivity.
