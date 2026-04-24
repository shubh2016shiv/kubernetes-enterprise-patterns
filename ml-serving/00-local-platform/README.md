# 00-local-platform

This module explains the local platform choices for model serving work.

## What To Read First

Start with `README.md` in `setup/` if you have not created a cluster yet. Then read [docker-desktop-kubernetes.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/ml-serving/00-local-platform/docker-desktop-kubernetes.md) as context for why a single-node local cluster behaves differently from the `kind` cluster used in this repository.

## Preferred Path

For this repository, the preferred path is:
- `setup/` creates the `kind` cluster
- `ml-serving/` deploys serving workloads onto that cluster
