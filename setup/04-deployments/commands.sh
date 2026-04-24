#!/usr/bin/env bash
# =============================================================================
# FILE:    commands.sh
# PURPOSE: Canonical runner for the Deployments module. It runs the rollout
#          walkthrough first, then the lifecycle observation drill.
# USAGE:   bash setup/04-deployments/commands.sh
# WHEN:    Run after setup/03-pods and before setup/05-services.
# PREREQS: Namespace `applications` exists and kubectl points at the learning cluster.
# OUTPUT:  Two sibling Deployments are created, the gateway is rolled and
#          rolled back, then pod restart/reschedule/scale behavior is observed.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Stage 1.0: Rollout and rollback mechanics
# Purpose: Teach Deployment revision behavior before disturbing live pods.
"${SCRIPT_DIR}/rolling-update.sh"

# Stage 2.0: Live lifecycle observation
# Purpose: Teach what an operator watches when pods change in real time.
"${SCRIPT_DIR}/observe-lifecycle.sh"
