#!/usr/bin/env bash
# =============================================================================
# FILE:    health-commands.sh
# PURPOSE: Backward-compatible wrapper for the Health Checks walkthrough.
# USAGE:   bash setup/09-health-checks/health-commands.sh
# WHEN:    Use this if older notes still reference health-commands.sh.
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
