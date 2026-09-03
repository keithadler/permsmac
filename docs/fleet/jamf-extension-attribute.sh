#!/bin/bash
# Jamf Pro extension attribute: is this Mac compliant with the permissions policy?
# Data type: String. Runs as root, so every account is checked.
# Install Permissions for Mac with a policy first, and put your policy at the path below.
PERMSMAC="/Applications/Permissions for Mac.app/Contents/MacOS/PermsMac"
POLICY="/Library/Management/permissions-policy.json"
if [ ! -x "$PERMSMAC" ]; then echo "<result>not installed</result>"; exit 0; fi
if [ ! -f "$POLICY" ]; then echo "<result>no policy</result>"; exit 0; fi
OUT=$("$PERMSMAC" audit "$POLICY" 2>&1); CODE=$?
case $CODE in
  0) echo "<result>compliant</result>" ;;
  1) echo "<result>violations: $(echo "$OUT" | head -n -1 | tr '\n' ';')</result>" ;;
  *) echo "<result>could not check: $OUT</result>" ;;
esac
