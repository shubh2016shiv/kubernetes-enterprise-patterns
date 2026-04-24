#!/usr/bin/env bash
# =============================================================================
# FILE:    apply-config.sh
# PURPOSE: Backward-compatible wrapper for the ConfigMaps and Secrets walkthrough.
# USAGE:   bash setup/06-configmaps-secrets/apply-config.sh
# WHEN:    Use this if older notes still reference apply-config.sh.
# PREREQS: Same as commands.sh: kubectl points at the learning cluster and the
#          `applications` namespace exists.
# OUTPUT:  Delegates to commands.sh, the canonical runner for this module.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Stage 1.0: Delegate to canonical module runner
# Purpose: Preserve the old entrypoint while following setup/AGENTS.md, which
# requires each command-driven module to expose commands.sh.
"${SCRIPT_DIR}/commands.sh"
