#!/usr/bin/env bash
# =============================================================================
# FILE: 02-namespaces/apply-namespaces.sh
# PURPOSE: Apply namespace definitions and explore the resulting structure.
#          Teaches namespace inspection commands used daily in enterprise.
# =============================================================================

set -e
set -u
set -o pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    NAMESPACE SETUP FLOW                                   │
# │                                                                           │
# │  Stage 1: Apply Declarative YAML                                         │
# │      └── kubectl apply -f namespaces.yaml                                │
# │                                                                           │
# │  Stage 2: List Cluster Namespaces                                        │
# │      └── kubectl get namespaces                                          │
# │                                                                           │
# │  Stage 3: Inspect Namespace Metadata                                     │
# │      └── kubectl describe namespace applications                         │
# │                                                                           │
# │  Stage 4: View Label Selectors                                           │
# │      └── kubectl get namespaces --show-labels                            │
# │                                                                           │
# │  Stage 5: Set Default Context                                            │
# │      └── Set current context namespace to 'applications'                 │
# └──────────────────────────────────────────────────────────────────────────┘

MANIFESTS_DIR="$(dirname "$0")"

echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Phase 2: Enterprise Namespace Setup${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"

# ─── STEP 1: APPLY NAMESPACES ─────────────────────────────────────────────────
# `kubectl apply` is the DECLARATIVE way to create/update resources.
# It compares what you declare in YAML to what currently exists in the cluster.
# If it doesn't exist → creates it
# If it exists but YAML changed → updates it
# If it exists and YAML is same → does nothing (shows "unchanged")
#
# ENTERPRISE RULE: Always use `kubectl apply` for ongoing resource management.
# NEVER use `kubectl create` in automation — `create` fails if resource exists.
# `apply` is idempotent; `create` is not.
echo ""
echo -e "${BOLD}[1] Applying namespace definitions...${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/namespaces.yaml"

echo ""
echo -e "${GREEN}✓ Namespaces applied!${RESET}"

# ─── STEP 2: LIST ALL NAMESPACES ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2] All namespaces in cluster:${RESET}"
echo ""

# `kubectl get namespaces` shows:
#   NAME     → The namespace name
#   STATUS   → Active (healthy) or Terminating (being deleted — graceful shutdown)
#   AGE      → How long ago it was created
kubectl get namespaces

# ─── STEP 3: INSPECT A NAMESPACE IN DETAIL ────────────────────────────────────
# `kubectl describe` is your go-to debug command for ANY K8s resource.
# It shows:
#   - Metadata (labels, annotations, creation time)
#   - Current status
#   - Events (recent activity on this resource — INVALUABLE for debugging)
echo ""
echo -e "${BOLD}[3] Detailed view of 'applications' namespace:${RESET}"
echo ""
kubectl describe namespace applications

# ─── STEP 4: SHOW LABELS (for selector understanding) ─────────────────────────
# Labels are the FOUNDATION of how Kubernetes selects resources.
# Services find Pods via labels. NetworkPolicies target namespaces via labels.
# Understanding label selectors is one of the most tested K8s interview topics.
echo ""
echo -e "${BOLD}[4] Namespace labels (used for NetworkPolicy and RBAC targeting):${RESET}"
echo ""
# --show-labels shows all labels as a final column in the output
kubectl get namespaces --show-labels

# ─── STEP 5: TEACH — DEFAULT NAMESPACE TRAP ───────────────────────────────────
echo ""
echo -e "${BOLD}[5] Enterprise Best Practice — Avoid the 'default' Namespace${RESET}"
echo ""
echo -e "  ${YELLOW}The 'default' namespace is a TRAP for beginners.${RESET}"
echo ""
echo -e "  Without specifying -n (namespace), kubectl commands target 'default'."
echo -e "  In enterprise, NOTHING runs in 'default'. Here's why:"
echo ""
echo -e "    1. No RBAC isolation   — everyone can read/write default"
echo -e "    2. No resource quotas  — one app can starve another"
echo -e "    3. No network policies — all pods can talk to all pods"
echo -e "    4. Audit nightmare     — who deployed what is unclear"
echo ""
echo -e "  ${CYAN}Always use: kubectl -n <namespace> <command>${RESET}"
echo -e "  ${CYAN}Or set a default: kubectl config set-context --current --namespace=applications${RESET}"

# ─── STEP 6: SET DEFAULT NAMESPACE IN CONTEXT ─────────────────────────────────
# This configures kubectl so that commands without -n default to "applications"
# instead of "default". This is how enterprise engineers set up their contexts.
#
# CONCEPT: A kubectl "context" = cluster + user + namespace
# You can have multiple contexts for the same cluster with different namespaces.
echo ""
echo -e "${BOLD}[6] Setting 'applications' as default namespace for this context${RESET}"
kubectl config set-context --current --namespace=applications
echo -e "  ${GREEN}✓ Done. Now 'kubectl get pods' targets 'applications' namespace${RESET}"
echo -e "  ${YELLOW}  To verify: kubectl config view --minify | grep namespace${RESET}"

echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  ✓ Namespace structure ready!${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Next step:${RESET} bash 03-pods/pod-commands.sh"
echo ""
