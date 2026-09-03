#!/bin/bash
# End-to-end run of the command line against synthetic databases. Nothing here reads the real ones.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${BIN:-.build/debug/PermsMac}"
[ -x "$BIN" ] || swift build >/dev/null
export PERMSMAC_HOME="$(mktemp -d)"
trap 'rm -rf "$PERMSMAC_HOME"' EXIT
export PERMSMAC_USER_DB="$PERMSMAC_HOME/user.db" PERMSMAC_SYSTEM_DB="$PERMSMAC_HOME/system.db"
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; echo "  command: $2"; fi; }

mk() { # file, rows as "service|client|auth"
  local db="$1"
  sqlite3 "$db" "CREATE TABLE IF NOT EXISTS access (service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL, auth_value INTEGER NOT NULL, auth_reason INTEGER NOT NULL, auth_version INTEGER NOT NULL, csreq BLOB, policy_id INTEGER, indirect_object_identifier_type INTEGER, indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED', indirect_object_code_identity BLOB, flags INTEGER, last_modified INTEGER NOT NULL DEFAULT 1756800000);"
  shift; for r in "$@"; do IFS='|' read -r s c a <<<"$r"; sqlite3 "$db" "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('$s','$c',0,$a,2,1);"; done
}
mk "$PERMSMAC_USER_DB" "kTCCServiceCamera|com.example.a|2" "kTCCServiceMicrophone|com.example.a|0"
mk "$PERMSMAC_SYSTEM_DB" "kTCCServiceScreenCapture|com.example.a|2"

check "version prints" '"$BIN" version | grep -q permsmac'
check "help exits 0" '"$BIN" help >/dev/null'
check "status sees both databases" '"$BIN" status --json | grep -q "\"fullDiskAccess\" : true"'
check "list shows allowed only" '[ "$("$BIN" list --json | grep -c "\"state\"")" = 2 ]'
check "list --all shows denied" '[ "$("$BIN" list --all --json | grep -c "\"state\"")" = 3 ]'
check "list --service filters" '"$BIN" list --service camera --json | grep -q kTCCServiceCamera && ! "$BIN" list --service camera --json | grep -q ScreenCapture'
check "bad service is usage error" '"$BIN" list --service nonsense >/dev/null 2>&1; [ $? = 64 ]'
check "orphans exit 1" '"$BIN" orphans --json >/dev/null; [ $? = 1 ]'
check "first changes: nothing" '"$BIN" changes --json >/dev/null; [ $? = 0 ]'
# Back-date the record, add a grant, look again.
python3 - "$PERMSMAC_HOME/history.json" <<'PY'
import json,sys,datetime
p=sys.argv[1]; r=json.load(open(p)); r[0]["date"]=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%SZ"); json.dump(r,open(p,"w"))
PY
mk "$PERMSMAC_SYSTEM_DB" "kTCCServiceAccessibility|com.example.b|2"
check "changes exit 1 after a grant" '"$BIN" changes --json >/dev/null; [ $? = 1 ]'
# `changes` exits 1 on purpose when something changed; with pipefail that must not fail the grep.
check "changes names the grant" '("$BIN" changes --json || true) | grep -q "kTCCServiceAccessibility|com.example.b"'
check "changes --since 1h still shows it (it was first seen just now)" '("$BIN" changes --since 1h --json || true) | grep -q Accessibility'
check "explain works" '"$BIN" explain "screen recording" | grep -qi "everything on your screen"'
check "startup runs" '"$BIN" startup --json | grep -q items'
check "history stays in PERMSMAC_HOME" '[ -f "$PERMSMAC_HOME/history.json" ]'
check "databases untouched" '[ -z "$(ls "$PERMSMAC_HOME" | grep -E "journal|wal|shm")" ]'
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
