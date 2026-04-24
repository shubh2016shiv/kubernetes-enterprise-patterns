#!/usr/bin/env bash
# =============================================================================
# FILE:    service-commands.sh
# PURPOSE: Preserve the older entrypoint name while redirecting learners to the
#          canonical module runner required by setup/AGENTS.md.
# USAGE:   bash setup/05-services/service-commands.sh
# WHEN:    Use this only if older notes or shell history still point here.
# PREREQS: Same prerequisites as commands.sh.
# OUTPUT:  Delegates to commands.sh and runs the full services walkthrough.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Thin compatibility wrapper:
# setup/AGENTS.md asks every module with commands to expose a canonical
# `commands.sh`. We keep this file so earlier instructions do not break.
exec "${SCRIPT_DIR}/commands.sh"
