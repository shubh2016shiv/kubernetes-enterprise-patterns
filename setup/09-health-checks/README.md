# 09-health-checks

## What are Health Checks?
Health checks (Probes) are how Kubernetes determines the state of your application inside its container. Kubernetes does not automatically know if your Java app is deadlocked or if your Python server is busy connecting to a database. You must tell Kubernetes how to check.
- **Liveness Probe**: "Are you broken?" (If no, K8s restarts the container).
- **Readiness Probe**: "Are you ready for traffic?" (If no, K8s stops sending traffic, but doesn't restart the container).
- **Startup Probe**: "Are you done starting up?" (If no, K8s waits. Protects slow-starting legacy apps).

## Why does this exist?
In an enterprise environment, applications fail. They get deadlocked, they run out of database connections, they take 45 seconds to load machine learning models into memory. Without health checks, Kubernetes will send traffic to a container the millisecond the Linux process starts, resulting in hundreds of 502/503 errors while the app warms up.

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                    KUBERNETES PROBE LIFECYCLE              │
│                                                            │
│                  Container Process Starts                  │
│                             │                              │
│                             ▼                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  STARTUP PROBE                       │  │
│  │  Is the app fully initialized? (e.g. models loaded)  │  │
│  │  (Pauses all other probes until it succeeds)         │  │
│  └──────────────────────────┬───────────────────────────┘  │
│                             │ Success                      │
│        ┌────────────────────┴────────────────────┐         │
│        ▼                                         ▼         │
│  ┌───────────────┐                         ┌───────────────┐
│  │LIVENESS PROBE │                         │READINESS PROBE│
│  │Runs constantly│                         │Runs constantly│
│  └───────┬───────┘                         └───────┬───────┘
│          │                                         │       │
│  If fails 3 times                          If fails 3 times│
│          │                                         │       │
│          ▼                                         ▼       │
│ ┌─────────────────┐                       ┌────────────────┐
│ │ RESTART POD     │                       │ REMOVE FROM    │
│ │ (Kill process)  │                       │ LOAD BALANCER  │
│ └─────────────────┘                       └────────────────┘
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **Review Probes**: Check `startup-probe.yaml`, `liveness-probe.yaml`, and `readiness-probe.yaml` to see how the syntax differs and what they are used for.
2. **Combined Demo**: Review `health-checks-demo.yaml`. This shows how a real enterprise deployment uses all three together.
3. **Apply and Watch**: Run the `health-commands.sh` script to see how K8s reacts when probes fail.

## Commands

### 1. Apply and Observe Probes
```bash
bash setup/09-health-checks/health-commands.sh
```

**What you should see**:
```
=== Stage 1: Apply Health Check Demo ===
deployment.apps/health-check-demo created

=== Stage 2: Observe Probe Behavior ===
NAME                                READY   STATUS    RESTARTS   AGE
health-check-demo-6d9b9c9b6b-8x4j   0/1     Running   0          5s
...
```

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| HTTP GET `/` | Custom `/health` endpoints | An app might return 200 OK on `/` but have a broken DB connection. Enterprises build deep health checks that verify dependencies (DB, Redis) on `/health/ready`. |
| Basic `exec` probes | gRPC health probes | For gRPC microservices, standard HTTP probes don't work. Enterprises use native gRPC health checking protocols. |
| Fast Liveness restarts | Generous Liveness timeouts | A common anti-pattern is a Liveness probe that restarts an app because the network was slow for 2 seconds. Enterprise liveness probes are very forgiving to avoid needless CrashLoops. |

## What to Check If Something Goes Wrong

1. **CrashLoopBackOff**: Your Liveness probe is failing. `kubectl describe pod <name> -n applications` will show `Liveness probe failed: HTTP probe failed with statuscode: 500` in the Events section.
2. **Pod is Running, but READY is 0/1**: Your Readiness probe is failing. The container is alive, but K8s won't send traffic to it. Check the Events section as well.
3. **App takes 60 seconds to start, but gets killed after 10s**: You forgot a Startup probe, and your Liveness probe killed the app before it could finish starting. Add a Startup probe with a generous `failureThreshold`.
