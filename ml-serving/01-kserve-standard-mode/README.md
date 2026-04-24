# 01-kserve-standard-mode

This module installs the KServe control plane in Standard mode.

## File Order

1. `install-kserve-standard-mode.sh`: installs CRDs and controller resources.
2. `verify-kserve.sh`: confirms the serving control plane is healthy.

## Why Standard Mode First

Standard mode is easier to reason about because it generates ordinary Kubernetes Deployments and Services. That makes it the right first mental model before introducing more advanced request-driven serving stacks.
