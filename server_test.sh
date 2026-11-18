#!/bin/bash
# =============================================================================
# Server Test Script
# Tests: machine operability, firewall config, connectivity, security, recovery
# Author: Jesus Junco
# =============================================================================

# --- Configuration ---
COMPARTIDA_DIR="/home/vmjesus/compartida"
SAMBA_USER="vmjesus"
SSH_PORT=22
SAMBA_PORT=445
BACKUP_TEST_DIR="/tmp/recovery_test_backup"

# --- Counters ---
PASS=0
FAIL=0
WARN=0

# --- Helpers ---
pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }
warn() { echo "[WARN] $1"; WARN=$((WARN+1)); }
section() { echo; echo "=================================================="; echo " $1"; echo "=================================================="; }

# =============================================================================
# 1. MACHINE OPERABILITY
# =============================================================================
section "1. MACHINE OPERABILITY"

# Uptime and load
echo "--- Uptime & Load ---"
uptime

# Memory
echo
echo "--- Memory ---"
free -h

# Disk on root
echo
echo "--- Disk (/) ---"
df -h / | tail -n +1

# Critical services
echo
echo "--- Critical Services ---"
for svc in ssh smbd; do
    if systemctl is-active --quiet "$svc"; then
        pass "Service '$svc' is active"
    else
        fail "Service '$svc' is NOT active"
    fi
done

# =============================================================================
# 2. FIREWALL CONFIGURATION (UFW)
# =============================================================================
section "2. FIREWALL CONFIGURATION (UFW)"

if ! command -v ufw >/dev/null 2>&1; then
    fail "UFW is not installed"
else
    # Is UFW active?
    UFW_STATUS=$(sudo ufw status | head -n1)
    echo "--- UFW Status ---"
    echo "$UFW_STATUS"
    if echo "$UFW_STATUS" | grep -qi "active"; then
        pass "UFW is active"
    else
        fail "UFW is NOT active"
    fi

    # Dump rules
    echo
    echo "--- UFW Rules ---"
    sudo ufw status verbose

    # Expected ports
    echo
    echo "--- Expected Port Checks ---"
    RULES=$(sudo ufw status)
    if echo "$RULES" | grep -qE "${SSH_PORT}(/tcp)?[[:space:]]+ALLOW"; then
        pass "SSH port $SSH_PORT is allowed"
    else
        fail "SSH port $SSH_PORT is NOT explicitly allowed"
    fi

    if echo "$RULES" | grep -qE "Samba"; then
        pass "Samba is explicitly allowed in UFW"
    elif echo "$RULES" | grep -qE "${SAMBA_PORT}/tcp[[:space:]]+ALLOW"; then
        pass "Samba port $SAMBA_PORT is allowed"
    else
        warn "Samba port $SAMBA_PORT not found as an explicit rule (may be allowed via app profile)"
    fi

    # Default policies
    echo
    echo "--- Default Policies ---"
    DEFAULT_POLICY=$(sudo ufw status verbose | grep -i "Default:")
    echo "$DEFAULT_POLICY"
    if echo "$DEFAULT_POLICY" | grep -qi "deny (incoming)"; then
        pass "Default incoming policy is DENY (secure)"
    else
        warn "Default incoming policy is not DENY — review this"
    fi
fi

# =============================================================================
# 3. CONNECTIVITY
# =============================================================================
section "3. CONNECTIVITY"

# Network interfaces
echo "--- IP Addresses ---"
ip -brief addr show

echo
echo "--- Default Route ---"
if ip route | grep -q "^default"; then
    ip route | grep "^default"
    pass "Default route exists"
else
    fail "No default route found"
fi

# Listening ports
echo
echo "--- Listening Ports (SSH & Samba) ---"
if ss -tlnp 2>/dev/null | grep -q ":${SSH_PORT} "; then
    pass "SSH is listening on port $SSH_PORT"
else
    fail "SSH is NOT listening on port $SSH_PORT"
fi

if ss -tlnp 2>/dev/null | grep -qE ":(139|445) "; then
    pass "Samba is listening on ports 139/445"
else
    fail "Samba is NOT listening on ports 139/445"
fi

# Local loopback connect test (proves service accepts connections)
echo
echo "--- Local Connection Tests ---"
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${SSH_PORT}" 2>/dev/null; then
    pass "Local TCP connect to SSH ($SSH_PORT) succeeded"
else
    fail "Local TCP connect to SSH ($SSH_PORT) failed"
fi

if timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${SAMBA_PORT}" 2>/dev/null; then
    pass "Local TCP connect to Samba ($SAMBA_PORT) succeeded"
else
    fail "Local TCP connect to Samba ($SAMBA_PORT) failed"
fi

# Ping gateway (connectivity beyond the host)
GATEWAY=$(ip route | awk '/^default/ {print $3; exit}')
if [ -n "$GATEWAY" ]; then
    echo
    echo "--- Ping Gateway ($GATEWAY) ---"
    if ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1; then
        pass "Gateway $GATEWAY is reachable"
    else
        warn "Gateway $GATEWAY did not respond to ping (could be blocked)"
    fi
fi

# =============================================================================
# 4. SECURITY
# =============================================================================
section "4. SECURITY"

# SSH hardening
echo "--- SSH Configuration ---"
if [ -f /etc/ssh/sshd_config ]; then
    ROOT_LOGIN=$(grep -iE "^\s*PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}' | tail -n1)
    if [ "$ROOT_LOGIN" = "no" ] || [ "$ROOT_LOGIN" = "prohibit-password" ]; then
        pass "SSH root login is restricted (PermitRootLogin=$ROOT_LOGIN)"
    else
        warn "SSH PermitRootLogin not set to 'no' (current: ${ROOT_LOGIN:-default})"
    fi
else
    fail "/etc/ssh/sshd_config not found"
fi

# Root login attempt test (should fail)
echo
echo "--- Root SSH Login Attempt (expected to fail) ---"
if timeout 5 ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@127.0.0.1 true 2>/dev/null; then
    fail "Root SSH login succeeded — this is a security issue"
else
    pass "Root SSH login was denied (good)"
fi

# Samba authentication — try listing shares without credentials
echo
echo "--- Samba Anonymous Access Test ---"
if command -v smbclient >/dev/null 2>&1; then
    if smbclient -L localhost -N >/dev/null 2>&1; then
        warn "Anonymous Samba share listing succeeded — consider requiring auth"
    else
        pass "Anonymous Samba listing denied (authentication required)"
    fi
else
    warn "smbclient not installed — skipping anonymous access test"
fi

# UFW default policy recap (already checked in section 2, but restate for security)
echo
echo "--- Firewall Policy Summary ---"
sudo ufw status verbose | grep -i "Default:" || warn "Could not read UFW default policy"


# =============================================================================
# 5. RECOVERY TEST (verify existing backup, no new backup run)
# =============================================================================
section "5. RECOVERY TEST (existing backup check)"

# --- Configuration ---
COMPARTIDA_DIR="${COMPARTIDA_DIR:-/srv/samba/compartida}"
SAMBA_USER="${SAMBA_USER:-vmjesus}"
BACKUP_ROOT="${BACKUP_ROOT:-/backup/compartida}"
RESTORE_TEST_DIR="/tmp/recovery_restore_test"

# 5.1 Shared folder exists
if [ -d "$COMPARTIDA_DIR" ]; then
    pass "Shared folder exists: $COMPARTIDA_DIR"
else
    fail "Shared folder NOT found: $COMPARTIDA_DIR"
fi

# 5.2 Samba user exists
if id "$SAMBA_USER" >/dev/null 2>&1; then
    pass "User '$SAMBA_USER' exists"
else
    fail "User '$SAMBA_USER' does NOT exist"
fi

# 5.3 A backup must exist
LATEST_BACKUP=""
if [ -d "$BACKUP_ROOT" ]; then
    LATEST_BACKUP=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "backup_*" \
                    | sort | tail -n1)
fi

if [ -n "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
    pass "Latest backup found: $LATEST_BACKUP"

    # 5.4 Backup is non-empty
    FILE_COUNT=$(find "$LATEST_BACKUP" -type f | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        pass "Backup contains $FILE_COUNT file(s)"
    else
        fail "Backup is EMPTY — nothing to restore"
    fi

    # 5.5 Restore into a temp dir and verify against the live share
    echo
    echo "--- Restoring a sample into $RESTORE_TEST_DIR ---"
    rm -rf "$RESTORE_TEST_DIR"
    mkdir -p "$RESTORE_TEST_DIR"

    SAMPLE_FILE=$(find "$LATEST_BACKUP" -type f | head -n1)
    if [ -z "$SAMPLE_FILE" ]; then
        fail "No file available in backup to test restore"
    else
        REL_PATH="${SAMPLE_FILE#$LATEST_BACKUP/}"
        echo "Sample file: $REL_PATH"

        if cp "$SAMPLE_FILE" "$RESTORE_TEST_DIR/"; then
            pass "Sample file restored from backup"
        else
            fail "Could not copy sample file from backup"
        fi

        # 5.6 Compare restored copy with the live original (if it exists)
        LIVE_FILE="${COMPARTIDA_DIR}/${REL_PATH}"
        if [ -f "$LIVE_FILE" ]; then
            if cmp -s "$SAMPLE_FILE" "$LIVE_FILE"; then
                pass "Restored content matches live file — backup is valid"
            else
                warn "Restored content differs from live file (may be a newer edit)"
            fi
        else
            warn "Original no longer exists in share; cannot compare contents"
        fi
    fi

    # 5.7 Check readability by the Samba user
    echo
    echo "--- Readability check as $SAMBA_USER ---"
    if id "$SAMBA_USER" >/dev/null 2>&1; then
        if sudo -u "$SAMBA_USER" test -r "$LATEST_BACKUP" 2>/dev/null; then
            pass "Backup is readable by $SAMBA_USER"
        else
            warn "$SAMBA_USER cannot read the backup dir (check permissions)"
        fi
    fi

    # Cleanup temp restore dir
    rm -rf "$RESTORE_TEST_DIR"
    echo "Temp restore directory removed."

else
    fail "No backup found under $BACKUP_ROOT (expected a backup_* directory)"
    warn "Run your backup script first, then re-run this test"
fi

# =============================================================================
# SUMMARY
# =============================================================================
section "SUMMARY"
echo "PASS: $PASS"
echo "WARN: $WARN"
echo "FAIL: $FAIL"
echo
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: All critical checks passed."
    exit 0
else
    echo "RESULT: $FAIL check(s) failed — review above."
    exit 1
fi
