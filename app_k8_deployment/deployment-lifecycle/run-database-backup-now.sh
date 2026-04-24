#!/usr/bin/env bash
# =============================================================================
# FILE:    run-database-backup-now.sh
# PURPOSE: Trigger the database backup CronJob immediately for learning/testing.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/run-database-backup-now.sh
# WHEN:    Run after deploying the backup CronJob.
# PREREQS: backup-patient-record-database CronJob exists.
# OUTPUT:  A one-off backup Job completes and writes a dump to the backup PVC.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify the CronJob exists.
#
# Stage 2: Create One-Off Backup Job
#   - Create a timestamped Job from the CronJob template.
#
# Stage 3: Wait and Inspect
#   - Wait for completion and print logs.
# ---------------------------------------------------------------------------

NAMESPACE="patient-record-system"
JOB_NAME="manual-patient-db-backup-$(date +%Y%m%d%H%M%S)"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "$ $*"
  "$@"
  echo ""
}

# ---------------------------------------------------------------------------
# Stage 1.0: Preflight Checks
# Purpose: Confirm the backup schedule exists before creating a manual run.
# Expected input: deploy-patient-record-system.sh has applied the CronJob.
# Expected output: CronJob lookup succeeds.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl get cronjob backup-patient-record-database -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 2.0: Create One-Off Backup Job
# Purpose: Run backup now instead of waiting until 02:00.
# Expected output: Kubernetes creates a Job from the CronJob template.
# ---------------------------------------------------------------------------
section "Stage 2.0: Create One-Off Backup Job"

echo "ENTERPRISE EMPHASIS: Backup schedules are only useful if restore drills prove the files can actually recover data."
run_cmd kubectl create job "${JOB_NAME}" \
  --from=cronjob/backup-patient-record-database \
  -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 3.0: Wait and Inspect
# Purpose: Prove the backup command completed and show the output path.
# Expected output: Job completes and logs show a .sql.gz file path.
# ---------------------------------------------------------------------------
section "Stage 3.0: Wait and Inspect"

run_cmd kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl logs "job/${JOB_NAME}" -n "${NAMESPACE}"

echo "Restore pattern:"
echo "  Use restore-database-backup.sh with the /backups/<file>.sql.gz path printed above."

