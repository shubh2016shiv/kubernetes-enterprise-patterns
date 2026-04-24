# 02-namespaces

This module introduces the first real enterprise habit inside a Kubernetes cluster: putting workloads into deliberate namespaces instead of dropping everything into `default`.

If you currently have zero idea what a namespace is, that is completely fine. This guide assumes that and starts from first principles.

## Stage 0.0 - What A Namespace Actually Is

A namespace is a logical boundary inside one Kubernetes cluster.

The easiest first mental model is:

```text
one Kubernetes cluster
    |
    +--> namespace A
    +--> namespace B
    +--> namespace C
```

So a namespace is not:
- not a separate cluster
- not a Docker container
- not a Linux process
- not a VM
- not a physical machine

It is a Kubernetes object that helps organize and isolate many resources inside the same cluster.

## Stage 0.1 - Where A Namespace “Sits” Internally

This is the part most beginners are not told clearly enough.

Internally, a namespace lives as data in the Kubernetes control plane.

More specifically:
- the Kubernetes API server stores namespace objects
- the cluster database `etcd` persists them
- controllers and `kubectl` use the namespace field to decide which resources belong together

You can think of it like this:

```text
Kubernetes API
    |
    v
Namespace object stored in etcd
    |
    v
Other resources reference that namespace
```

Example:
- a Pod in `applications`
- a Service in `applications`
- a ConfigMap in `applications`

all belong to the same namespace because their metadata says so.

That means a namespace is not “around” the Pod like a Linux cgroup or Docker network. It is a control-plane classification and boundary mechanism used by Kubernetes itself.

## Stage 0.2 - What A Namespace Does For You

A namespace helps Kubernetes answer:
- which team or environment owns this resource?
- which resources belong together?
- which RBAC rules apply here?
- which quotas apply here?
- which labels and policies target this group?

This is why namespaces are one of the first enterprise concepts after cluster creation.

## Stage 0.3 - What A Namespace Does NOT Automatically Do

This is extremely important.

A namespace does **not** automatically mean:
- network traffic is blocked between namespaces
- CPU or memory is limited
- users are restricted by default
- secrets are magically protected from everyone

Those protections require other Kubernetes features:
- NetworkPolicy for traffic rules
- ResourceQuota and LimitRange for resource control
- RBAC for access control

So the correct mental model is:

```text
namespace = organizational and policy boundary
not
namespace = complete security sandbox by itself
```

## Stage 1.0 - Why Enterprises Care So Much About Namespaces

In a real company, one cluster can host many things at once:
- applications
- monitoring
- security tools
- ingress controllers
- staging workloads

If everything lived in `default`, you would quickly lose:
- ownership clarity
- policy boundaries
- cost visibility
- operational safety

That is why this repository teaches namespaces early.

## Stage 1.1 - Built-In Namespaces You Already Have

Every new cluster already includes a few namespaces created by Kubernetes itself:

- `default`
- `kube-system`
- `kube-public`
- `kube-node-lease`

What they mean:

### `default`

This is where resources go if you do not specify a namespace.

Why beginners get trapped here:
- commands work without extra typing
- so people keep using it
- then later they have no clean boundaries

### `kube-system`

This contains Kubernetes system components such as:
- CoreDNS
- kube-proxy
- networking components

You usually inspect this namespace, but do not treat it like your application area.

### `kube-public`

Used for cluster-readable information.

### `kube-node-lease`

Used by node heartbeat/lease objects.

## Stage 2.0 - What This Module Creates

This module creates an enterprise-style namespace layout for the learning cluster:

- `applications`
- `monitoring`
- `security`
- `ingress-system`
- `staging`

Why these were chosen:
- they teach workload separation
- they map to common enterprise platform areas
- later modules can target them with labels and policies

## Stage 2.1 - Why These Particular Namespaces Exist

### `applications`

This is where most of the learning workloads will run.

Think of it as your main app area.

### `monitoring`

This is where tools like Prometheus and Grafana would live.

Why separate it:
- monitoring should not compete directly with app workloads
- monitoring often needs special permissions

### `security`

This is for highly privileged platform/security tools.

Examples:
- Vault
- cert-manager
- policy engines

### `ingress-system`

This is where ingress controllers or traffic entry components would live.

### `staging`

This lets the learner see that the same cluster can contain different environments.

In very large enterprises, staging is often a separate cluster, but using a namespace here teaches the basic separation idea first.

## Stage 3.0 - File Order

Open and use the files in this order:

1. `namespaces.yaml`
2. `apply-namespaces.sh`

Why this order matters:
- the YAML defines the desired namespace layout
- the script applies that layout and teaches you how to inspect it

## Stage 3.1 - Read The YAML Before Applying It

Open:

- [namespaces.yaml](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/02-namespaces/namespaces.yaml)

What to notice:
- each namespace has a name
- each namespace has labels
- each namespace has annotations

Why labels matter:
- later modules use them for policy targeting
- labels are how Kubernetes and its tooling select groups of resources

Why annotations matter:
- they are descriptive metadata
- they help humans and tools understand ownership and intent

## Stage 4.0 - Apply The Namespaces

Run:

```bash
cd "/path/to/kubernetes_architure"
bash setup/02-namespaces/apply-namespaces.sh
```

## Stage 4.1 - What `apply-namespaces.sh` Actually Does

The script performs these stages:

1. applies the namespace YAML
2. lists all namespaces
3. describes the `applications` namespace
4. shows labels on namespaces
5. explains why `default` is dangerous
6. sets your current context’s default namespace to `applications`

Why this is useful:
- it does not just create things
- it also teaches you how to inspect and think about them

## Stage 4.2 - The Most Important Beginner Lesson: The `default` Namespace Trap

If you run a command without `-n <namespace>`, Kubernetes often targets `default`.

Example:

```bash
kubectl get pods
```

This does **not** mean:
- “get all pods in the cluster”

It usually means:
- “get pods in the current namespace”

That is why namespace awareness matters so early.

## Stage 5.0 - Commands You Should Run Manually After The Script

Run these yourself:

```bash
kubectl get namespaces
kubectl get namespaces --show-labels
kubectl describe namespace applications
kubectl config view --minify | grep namespace
```

What each one teaches:

### `kubectl get namespaces`

Shows the cluster’s namespace list.

### `kubectl get namespaces --show-labels`

Shows the labels attached to each namespace.

This matters because labels are how later policies target namespaces.

### `kubectl describe namespace applications`

Shows:
- labels
- annotations
- status
- event information

This is your first example of the general Kubernetes habit:

```text
if confused -> use kubectl describe
```

### `kubectl config view --minify | grep namespace`

Shows which namespace your current context will target by default.

## Stage 6.0 - A Namespace Example That Makes It Concrete

Imagine later you create:
- a Pod named `web-1`
- a Service named `web-service`
- a ConfigMap named `web-config`

If all three are in the `applications` namespace:
- they belong to the same application area
- `kubectl -n applications get ...` can find them
- policies targeting `applications` can affect them

If another Pod named `web-1` exists in `staging`, that is allowed.

Why?
- names only need to be unique inside the same namespace for many resource types

So namespaces also help prevent naming collisions.

## Stage 7.0 - If Something Feels Confusing

### “Why don’t I see my pods?”

Possible reason:
- you are looking in the wrong namespace

Try:

```bash
kubectl get pods -A
kubectl get pods -n applications
```

`-A` means all namespaces.

### “Did Kubernetes really create my namespace?”

Check:

```bash
kubectl get namespace applications -o yaml
```

This shows the raw stored object.

### “Where is the namespace stored?”

Answer:
- as a Namespace object in the control plane
- persisted in `etcd`

Not:
- not as a Linux folder
- not as a Docker network by itself

## Stage 8.0 - First-Time Learner Command Sequence

Use this if you want the shortest practical flow:

```bash
cd "/path/to/kubernetes_architure"

# 1. Read the namespace definitions
less setup/02-namespaces/namespaces.yaml

# 2. Apply the namespace layout
bash setup/02-namespaces/apply-namespaces.sh

# 3. Explore the result
kubectl get namespaces
kubectl get namespaces --show-labels
kubectl describe namespace applications
```

## Stage 9.0 - If You Come Back Later And Forget Everything

Use this restart recipe:

```bash
cd "/path/to/kubernetes_architure"
bash setup/02-namespaces/apply-namespaces.sh
kubectl get namespaces --show-labels
kubectl describe namespace applications
```

## Most Important Things To Remember

- a namespace is a Kubernetes control-plane boundary, not a machine
- it helps organize and target resources inside one cluster
- it does not automatically enforce all security or traffic isolation
- later features like RBAC, quotas, and NetworkPolicy build on top of namespaces

## What Comes Next

Once namespaces make sense, move to:

- [03-pods/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/03-pods/README.md)

Why Pods come next:
- now that you understand where workloads live, the next step is learning the smallest workload unit itself
