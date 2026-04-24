# setup/AGENTS.md — Local Instructions for the Kubernetes Fundamentals Track
#
# =============================================================================
# DEFER TO ROOT FIRST
# =============================================================================
# All global rules live in the root AGENTS.md.
# Read the root AGENTS.md COMPLETELY before reading this file.
# This file ONLY adds specializations that apply inside setup/.
# It does NOT duplicate or override any root rules.
# =============================================================================

## Scope

This file governs agent behavior inside the `setup/` directory only.

`setup/` is the Kubernetes fundamentals track. It teaches the platform
primitives in the same order a senior platform engineer would explain them
to a new teammate: cluster creation → namespaces → pods → controllers →
networking → configuration → RBAC → resource governance → health probes →
enterprise reliability patterns.

---

## Local Additions for setup/

### Module Sequencing Rule

Every module in `setup/` builds on the previous one. When adding or modifying
content in any `setup/NN-*` folder, verify that:
- The concept introduced does not require knowledge of a later module.
- The README.md cross-references the previous module where relevant.
- The README.md tells the learner what comes next.

### YAML Splitting Rule

If a single YAML file covers more than one distinct Kubernetes concept,
split it into numbered files:
- `01-dev-namespace.yaml` — one concept per file
- `02-staging-namespace.yaml`

Numbered prefixes enforce the reading/apply order. Do not use alphabetical
naming when apply order matters.

### Script Location Rule

Every module that has commands must have a `commands.sh` file.
Do not put module-specific commands only in the README — also put them in a
runnable script with stage markers so the learner can execute them directly.

### The Fundamentals-Only Rule

The `setup/` track teaches Kubernetes primitives only. It does not introduce:
- Helm charts (except as a mention with a forward reference to ml-serving/)
- KServe or any serving platform
- ML/model-specific resources

If model-serving knowledge is needed to explain a concept, add a forward
reference and link to the ml-serving/ track instead of mixing concerns.

### Platform Notes in This Track

When explaining cluster-level behavior, always anchor it to the three major
managed Kubernetes platforms that learners will encounter in enterprise interviews:

- **AWS EKS** — the most common in enterprise (especially in the US)
- **Google GKE** — most common for ML/AI workloads
- **Azure AKS** — dominant in enterprises with Microsoft ecosystems

Every enterprise translation table must include at least one of these.
