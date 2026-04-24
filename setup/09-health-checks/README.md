# 09-health-checks

## What is this?
This module teaches Kubernetes health checks, also called probes. Probes are kubelet checks that decide whether a container has started, whether it is still alive, and whether it should receive traffic. In `08-resource-management/`, we controlled how much CPU and memory a workload may consume. This module teaches Kubernetes how to react when that workload is running but not actually healthy.

## Why does this exist?
Kubernetes can see that a container process exists, but it cannot automatically understand whether the application inside the container is useful. A Python API can deadlock, a Java service can still be warming up, and a gateway can be alive while its dependency pool is exhausted. Probes turn application-specific health into Kubernetes decisions: wait longer, restart the container, or remove the pod from Service endpoints.

## ASCII concept diagram

```text
POD HEALTH DECISION FLOW

  Container starts
        |
        v
  startupProbe
    Question: did the application finish booting?
    Failure: keep trying until threshold, then restart container
    Why: protects slow-starting apps from being killed too early
        |
        v
  livenessProbe                    readinessProbe
    Question: am I broken?           Question: should I receive traffic?
    Failure: restart container       Failure: remove pod from Service endpoints
    Use for app self-health          Use for traffic safety and dependency readiness

        |
        v
  Human debugging still needs:
    kubectl describe pod
    kubectl logs
    kubectl logs --previous
    kubectl get events

  Key lesson:
    Probes give Kubernetes a decision signal.
    Logs and events give humans visibility into the black box.
```

## Learning steps

1. Read [startup-probe.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/09-health-checks/startup-probe.yaml) to see the probe that protects slow-starting applications.
2. Read [liveness-probe.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/09-health-checks/liveness-probe.yaml) to see the probe that restarts broken containers.
3. Read [readiness-probe.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/09-health-checks/readiness-probe.yaml) to see the probe that controls whether a pod is included in Service endpoints.
4. Read [health-checks-demo.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/09-health-checks/health-checks-demo.yaml) to see a Deployment and Service working together so readiness can be observed through endpoints.
5. Run [commands.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/09-health-checks/commands.sh) to apply the demo, wait for readiness, inspect probe events, inspect logs, and review the debugging runbook.
6. Move next to an observability/debugging module before enterprise reliability patterns. This repository currently has `10-enterprise-patterns/`, but your black-box pod question is important enough that I recommend adding a dedicated `10-observability-debugging/` module and shifting enterprise patterns after it.

## Commands

Run the walkthrough from the repository root in WSL2:

```bash
bash setup/09-health-checks/commands.sh
```

What you should see on the happy path:

```text
=== Stage 1.0: Preflight Checks ===
applications namespace exists

=== Stage 2.0: Apply Health Check Demo ===
deployment.apps/probes-demo created
service/probes-demo-service created

=== Stage 3.0: Watch Readiness and Endpoints ===
pod/probes-demo-... condition met
probes-demo-service   10.x.x.x:80,10.x.x.x:80

=== Stage 4.0: Inspect Probe State ===
Conditions:
  Ready True
Events:
  ...

=== Stage 5.0: Inspect Logs for Human Visibility ===
... nginx access/startup logs ...
```

Useful manual commands:

```bash
kubectl get pods -n applications -l app=probes-demo -w
kubectl get endpoints probes-demo-service -n applications -w
kubectl describe pod <pod-name> -n applications
kubectl logs <pod-name> -n applications
kubectl logs <pod-name> -n applications --previous
kubectl get events -n applications --sort-by=.lastTimestamp
kubectl delete -f setup/09-health-checks/health-checks-demo.yaml
```

If older notes still reference the previous entrypoint, it now delegates to the canonical runner:

```bash
bash setup/09-health-checks/health-commands.sh
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Probe nginx `/` | Probe dedicated `/healthz`, `/readyz`, or `/startupz` endpoints | Root paths can return 200 even when real dependencies are broken. |
| Use HTTP probes | HTTP, TCP, exec, or gRPC probes depending on workload protocol | Enterprise fleets include REST APIs, gRPC services, workers, databases, and batch processors. |
| Observe readiness through a local Service endpoint | Same endpoint behavior behind ALB, GCLB, Application Gateway, or service mesh | Load balancers and meshes depend on readiness to avoid routing traffic to bad pods. |
| Inspect logs with `kubectl logs` | Centralized logs in Loki, CloudWatch, Datadog, Splunk, or Elastic | `kubectl logs` is useful for one pod; enterprises need searchable history across many pods. |
| Inspect Events manually | Events shipped to monitoring and alerting systems | Events explain why Kubernetes acted, but they are short-lived and need aggregation. |
| Tune probe timings by hand | Tune from SLOs, startup profiles, and incident history | Bad probes can cause outages by restarting healthy-but-slow applications. |

## What to check if something goes wrong

1. Pod is `Running` but `READY` is `0/1`:
Readiness is failing. Run `kubectl describe pod <pod-name> -n applications` and inspect the Events section.

2. Pod is in `CrashLoopBackOff`:
Liveness or startup may be failing, or the application process may be exiting. Run `kubectl logs <pod-name> -n applications --previous` to see logs from the crashed container.

3. Service has no endpoints:
Run `kubectl get endpoints probes-demo-service -n applications`. If endpoints are empty, pods are not Ready or the Service selector does not match pod labels.

4. App takes a long time to start and keeps restarting:
The startupProbe window is too short or missing. Increase `failureThreshold * periodSeconds` enough to cover real startup time.

5. Liveness causes restarts when a database is down:
That is a probe design bug. Liveness should usually check whether the app process can recover, not whether every external dependency is healthy.

6. You still cannot tell what the app is doing:
That is not a probe problem. Use logs, Events, exec, metrics, traces, and dashboards. This deserves a dedicated observability/debugging module.

## Happy path: how to read the output

1. Deployment is created:
Kubernetes now has pods with startup, liveness, and readiness probes.

2. Service is created:
Readiness can now be observed through endpoint registration.

3. Pods become Ready:
Startup succeeded, readiness succeeded, and the pods are eligible for traffic.

4. Endpoints show pod IPs:
The Service is routing only to ready pods.

5. `describe pod` shows Conditions and Events:
This is where Kubernetes explains probe outcomes.

6. `kubectl logs` shows application output:
This is the beginning of black-box visibility. In production, those logs should flow to a central platform.
