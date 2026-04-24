# Enterprise Kubernetes Learning Environment

This folder is the Kubernetes fundamentals track for the repository. It is designed to teach the platform primitives in the same order a careful platform engineer would explain them to a new teammate.

## Why `setup/` Exists

Before model serving, GitOps, operators, or enterprise policy tooling make sense, the learner needs a solid mental model of:
- cluster creation
- namespace boundaries
- Pods and controllers
- service networking
- configuration boundaries
- RBAC
- quotas and limits
- health probes
- enterprise traffic and availability controls

That is what this track teaches.

## Preferred Local Platform

Use:
- Windows host plus WSL2, or native macOS/Linux
- Docker Desktop as the container engine
- `kind` for the Kubernetes cluster
- Bash-compatible scripts

This repository does not treat PowerShell as the primary Kubernetes learning path because enterprise Kubernetes administration is overwhelmingly Linux-shell oriented.

## Learning Order

1. [00-prerequisites/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/README.md)
2. [01-cluster-setup/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/01-cluster-setup/README.md)
3. [02-namespaces/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/02-namespaces/README.md)
4. [03-pods/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/03-pods/README.md)
5. [04-deployments/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/04-deployments/README.md)
6. [05-services/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/05-services/README.md)
7. [06-configmaps-secrets/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/06-configmaps-secrets/README.md)
8. [07-rbac/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/07-rbac/README.md)
9. [08-resource-management/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/08-resource-management/README.md)
10. [09-health-checks/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/09-health-checks/README.md)
11. [10-enterprise-patterns/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/10-enterprise-patterns/README.md)

## Directory Structure

```text
setup/
├── README.md
├── AGENTS.md
├── run-all.sh
├── 00-prerequisites/
│   ├── README.md
│   ├── check-prerequisites.sh
│   ├── install-guide.md
│   └── platform-guides/
├── 01-cluster-setup/
│   ├── README.md
│   ├── kind-cluster-config.yaml
│   ├── create-cluster.sh
│   ├── verify-cluster.sh
│   └── destroy-cluster.sh
├── 02-namespaces/
├── 03-pods/
├── 04-deployments/
├── 05-services/
├── 06-configmaps-secrets/
├── 07-rbac/
├── 08-resource-management/
├── 09-health-checks/
└── 10-enterprise-patterns/
```

## Quick Start

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/setup
bash 00-prerequisites/check-prerequisites.sh
bash 01-cluster-setup/create-cluster.sh
bash 01-cluster-setup/verify-cluster.sh
```

If you want the guided, pause-and-explore experience, run:

```bash
bash run-all.sh
```

If you want the spoon-fed version for cluster creation, open:

- [01-cluster-setup/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/01-cluster-setup/README.md)
- [01-cluster-setup/first-time-cluster-checklist.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/01-cluster-setup/first-time-cluster-checklist.md)

If you want the spoon-fed version for namespaces, open:

- [02-namespaces/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/02-namespaces/README.md)
- [02-namespaces/first-time-namespaces-checklist.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/02-namespaces/first-time-namespaces-checklist.md)

## After Fundamentals

When this track feels comfortable, move to [ml-serving/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/ml-serving/README.md) to learn how enterprise model-serving platforms build on these primitives.
