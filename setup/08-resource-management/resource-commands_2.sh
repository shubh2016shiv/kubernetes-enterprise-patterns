#!/usr/bin/env bash
# =============================================================================
# FILE:    resource-commands.sh
# PURPOSE: Backward-compatible wrapper for the Resource Management walkthrough.
# USAGE:   bash setup/08-resource-management/resource-commands.sh
# WHEN:    Use this if older notes still reference resource-commands.sh.
# PREREQS: Same as commands.sh: the `applications` namespace exists and kubectl
#          points at the learning cluster.
# OUTPUT:  Delegates to commands.sh, the canonical runner for this module.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Stage 1.0: Delegate to canonical module runner
# Purpose: Preserve the old entrypoint while following setup/AGENTS.md, which
# requires each command-driven module to expose commands.sh.
"${SCRIPT_DIR}/commands.sh"
