#!/usr/bin/env bash
# =============================================================================
# FILE:    restore-database-backup.sh
# PURPOSE: Restore the database from a backup file stored on the backup PVC.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/restore-database-backup.sh /backups/patient-record-db-YYYYMMDD-HHMMSS.sql.gz
# WHEN:    Run during a local restore drill after creating a backup.
# PREREQS: The backup file exists on the patient-record-database-backups PVC.
# OUTPUT:  A restore Job imports the SQL dump back into the database.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Validate Backup Path
#   - Require an explicit /backups/*.sql.gz path.
#
# Stage 2: Create Restore Job
#   - Start a temporary MariaDB client Job with backup PVC mounted.
#
# Stage 3: Wait and Inspect
#   - Wait for completion and print restore logs.
# ---------------------------------------------------------------------------

# CONFIGURATION EXPLANATION Restore runs in the same namespace as the database Service, credentials Secret, and
# backup PersistentVolumeClaim. Keeping these together makes the local restore drill explicit and auditable.
NAMESPACE="patient-record-system"
# CONFIGURATION EXPLANATION The restore input must be an explicit backup file path. This avoids guessing which
# backup to restore, which is dangerous in production because restoring the wrong file can overwrite valid data.
BACKUP_FILE="${1:-}"
# CONFIGURATION EXPLANATION The timestamped restore Job name creates a separate Kubernetes object for each
# restore drill, preserving logs and Events for troubleshooting.
JOB_NAME="manual-patient-db-restore-$(date +%Y%m%d%H%M%S)"

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
# Stage 1.0: Validate Backup Path
# Purpose: Avoid accidentally running restore with an empty or unsafe path.
# Expected input: A path printed by run-database-backup-now.sh.
# Expected output: BACKUP_FILE starts with /backups/ and ends with .sql.gz.
# ---------------------------------------------------------------------------
section "Stage 1.0: Validate Backup Path"

if [[ -z "${BACKUP_FILE}" || "${BACKUP_FILE}" != /backups/*.sql.gz ]]; then
  echo "ERROR: Provide a backup path like /backups/patient-record-db-YYYYMMDD-HHMMSS.sql.gz"
  exit 1
fi

echo "Backup file: ${BACKUP_FILE}"

# ---------------------------------------------------------------------------
# Stage 2.0: Create Restore Job
# Purpose: Run database restore as an explicit operational action.
# Expected output: A temporary restore Job is created.
# ---------------------------------------------------------------------------
section "Stage 2.0: Create Restore Job"

echo "ENTERPRISE EMPHASIS: Restore is the proof that backup works. In production, run restore drills in isolated environments before trusting a backup policy."
kubectl apply -n "${NAMESPACE}" -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
spec:
  backoffLimit: 1
  template:
    metadata:
      labels:
        app: restore-patient-record-database
    spec:
      serviceAccountName: patient-database-backup-runner
      restartPolicy: Never
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: restore
          image: mariadb:11.8.6
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          env:
            - name: MARIADB_DATABASE
              valueFrom:
                secretKeyRef:
                  name: patient-record-database-credentials
                  key: mysql-database
            - name: MARIADB_USER
              valueFrom:
                secretKeyRef:
                  name: patient-record-database-credentials
                  key: mysql-user
            - name: MARIADB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: patient-record-database-credentials
                  key: mysql-password
          command:
            - /bin/sh
            - -c
            - |
              set -eu
              test -f "${BACKUP_FILE}"
              gzip -dc "${BACKUP_FILE}" | mariadb \
                -h patient-record-database-service \
                -u"\${MARIADB_USER}" \
                -p"\${MARIADB_PASSWORD}" \
                "\${MARIADB_DATABASE}"
              echo "Restore completed from ${BACKUP_FILE}"
          volumeMounts:
            - name: backup-storage
              mountPath: /backups
      volumes:
        - name: backup-storage
          persistentVolumeClaim:
            claimName: patient-record-database-backups
YAML

# ---------------------------------------------------------------------------
# Stage 3.0: Wait and Inspect
# Purpose: Prove the restore completed successfully.
# Expected output: Job completes and logs report restore completion.
# ---------------------------------------------------------------------------
section "Stage 3.0: Wait and Inspect"

# CONFIGURATION EXPLANATION The 180s timeout turns restore into a clear operational gate. A restore that cannot
# complete quickly enough needs investigation before anyone trusts the recovered database.
run_cmd kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl logs "job/${JOB_NAME}" -n "${NAMESPACE}"
