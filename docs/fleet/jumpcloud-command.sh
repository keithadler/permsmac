#!/bin/bash
# JumpCloud command (run as root, on a daily schedule): write the audit and today's changes as JSON
# where your log shipper picks them up, and fail the command when the Mac is out of policy.
PERMSMAC="/Applications/Permissions for Mac.app/Contents/MacOS/PermsMac"
POLICY="/Library/Management/permissions-policy.json"
LOG="/var/log/permsmac"
mkdir -p "$LOG"
"$PERMSMAC" changes --since 1d --json > "$LOG/changes-$(date +%F).json"
"$PERMSMAC" audit "$POLICY" --json > "$LOG/audit-$(date +%F).json"; CODE=$?
"$PERMSMAC" list --json > "$LOG/inventory.json"
exit $CODE
