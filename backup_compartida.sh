#!/bin/bash
# =============================================================================
# Backup + Recovery Script for Samba 'compartida' share
# Author: Jesus Junco
#
# Usage:
#   backup_compartida.sh              -> run a normal backup
#   backup_compartida.sh --test-recovery -> run backup + full recovery test
# =============================================================================

# --- Configuration ---
SOURCE_DIR="/home/vmjesus/compartida"
BACKUP_ROOT="/backup/compartida"
SAMBA_USER="vmjesus"
LOG_FILE="/var/log/backup_compartida.log"
RETENTION_DAYS=7

# --- Setup ---
DATE=$(date +%F_%H%M%S)
DEST="${BACKUP_ROOT}/backup_${DATE}"
mkdir -p "$BACKUP_ROOT"
touch "$LOG_FILE"

log() { echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"; }

# =============================================================================
# BACKUP FUNCTION
# =============================================================================
run_backup() {
    log "Starting backup: $SOURCE_DIR -> $DEST"
    mkdir -p "$DEST"

    rsync -avz --delete "$SOURCE_DIR/" "$DEST/" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log "Backup SUCCESS: $DEST"
    else
        log "Backup FAILED"
        return 1
    fi

    # Retention: delete backups older than RETENTION_DAYS
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name "backup_*" \
         -mtime +"$RETENTION_DAYS" -exec rm -rf {} \; 2>/dev/null
    log "Retention applied (keep last $RETENTION_DAYS days)"
}

# =============================================================================
# RECOVERY TEST FUNCTION
# =============================================================================
run_recovery_test() {
    log "=== RECOVERY TEST START ==="

    TEST_FILE_NAME="recovery_test_$(date +%s).txt"
    TEST_FILE="${SOURCE_DIR}/${TEST_FILE_NAME}"
    TEST_CONTENT="Recovery test content — $(date)"
    TEST_BACKUP="${DEST}/${TEST_FILE_NAME}"

    # 1. Create test file as Samba user
    if sudo -u "$SAMBA_USER" bash -c "echo '$TEST_CONTENT' > '$TEST_FILE'" 2>>"$LOG_FILE"; then
        log "Step 1 OK: test file created as $SAMBA_USER"
    else
        log "Step 1 FAIL: could not create test file as $SAMBA_USER"
        return 1
    fi

    # 2. Re-run backup so the test file is included
    rsync -az "$SOURCE_DIR/" "$DEST/" >> "$LOG_FILE" 2>&1
    if [ -f "$TEST_BACKUP" ]; then
        log "Step 2 OK: backup contains test file"
    else
        log "Step 2 FAIL: test file not found in backup"
        return 1
    fi

    # 3. Simulate data loss
    rm -f "$TEST_FILE"
    if [ ! -f "$TEST_FILE" ]; then
        log "Step 3 OK: original deleted (data loss simulated)"
    else
        log "Step 3 FAIL: could not delete original"
        return 1
    fi

    # 4. Restore
    cp "$TEST_BACKUP" "$TEST_FILE" && chown "$SAMBA_USER":"$SAMBA_USER" "$TEST_FILE"
    if [ -f "$TEST_FILE" ]; then
        log "Step 4 OK: file restored from backup"
    else
        log "Step 4 FAIL: restore failed"
        return 1
    fi

    # 5. Verify content
    RESTORED_CONTENT=$(cat "$TEST_FILE")
    if [ "$RESTORED_CONTENT" = "$TEST_CONTENT" ]; then
        log "Step 5 OK: content matches — RECOVERY SUCCESSFUL"
        rm -f "$TEST_FILE"
        log "=== RECOVERY TEST PASSED ==="
        return 0
    else
        log "Step 5 FAIL: content mismatch — RECOVERY FAILED"
        return 1
    fi
}

# =============================================================================
# MAIN
# =============================================================================
if [ "$1" = "--test-recovery" ]; then
    run_backup || { log "Aborting recovery test: backup failed"; exit 1; }
    run_recovery_test
    exit $?
else
    run_backup
    exit $?
fi
