#!/usr/bin/env bash
# Probe macOS runner slots, keepawake assertions, and TCC permissions.
set -u

echo "=== Runner LaunchAgents ==="
launchctl list | grep -i actions.runner || echo "(none found)"

echo "=== Power / Keepawake ==="
pmset -g assertions | grep -i caffeinate || echo "(no caffeinate assertion)"

echo "=== Sudo (non-interactive) ==="
sudo -n true 2>/dev/null && echo "SUDO_NOPASS=YES" || echo "SUDO_NOPASS=NO"

echo "=== Accessibility (System Events) ==="
osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' >/dev/null 2>&1   && echo "ACCESSIBILITY=OK" || echo "ACCESSIBILITY=DENIED"

echo "=== Chrome Automation ==="
osascript -e 'tell application "Google Chrome" to count of windows' >/dev/null 2>&1   && echo "CHROME_AUTOMATION=OK" || echo "CHROME_AUTOMATION=DENIED"

echo "=== Screen Recording ==="
TMP_PNG="/tmp/gemini_perm_probe_$$.png"
screencapture -x "$TMP_PNG" >/dev/null 2>&1 && [ -s "$TMP_PNG" ]   && echo "SCREEN_RECORDING=OK" || echo "SCREEN_RECORDING=DENIED"
rm -f "$TMP_PNG"
