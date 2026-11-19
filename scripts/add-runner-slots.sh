#!/usr/bin/env bash
# Register additional macOS GitHub Actions Self-Hosted Runner slots for true multi-job concurrency.
# Usage:
#   ./scripts/add-runner-slots.sh <owner/repo> <label> [start_slot] [end_slot] [base_runner_dir]
# Example:
#   ./scripts/add-runner-slots.sh myuser/my-mac-bridge mac-bridge 2 3 "$HOME/Library/Application Support/mac-runner"
set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo> <label> [start_slot] [end_slot] [base_runner_dir]}"
LABEL="${2:?Usage: $0 <owner/repo> <label> [start_slot] [end_slot] [base_runner_dir]}"
START_SLOT="${3:-2}"
END_SLOT="${4:-3}"
BASE_DIR="${5:-$HOME/Library/Application Support/mac-runner}"
TARBALL="${BASE_DIR}/runner.tar.gz"

if [ ! -f "$TARBALL" ]; then
  echo "ERROR: runner tarball not found at $TARBALL" >&2
  echo "Download actions-runner-osx-arm64-*.tar.gz and save it as $TARBALL first." >&2
  exit 1
fi

get_token() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh api -X POST "repos/${REPO}/actions/runners/registration-token" -q .token
    return 0
  fi
  local cred_pw
  cred_pw=$(printf 'protocol=https
host=github.com

' | git credential fill | awk -F= '/^password=/{print $2; exit}')
  if [ -z "$cred_pw" ]; then
    echo "ERROR: neither gh CLI nor git credential helper returned a GitHub token." >&2
    exit 1
  fi
  curl -fsSL -X POST     -H "Authorization: Bearer ${cred_pw}"     -H "Accept: application/vnd.github+json"     "https://api.github.com/repos/${REPO}/actions/runners/registration-token"     | python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])'
}

HOST_PREFIX="$(whoami)-mac-bridge"
for slot in $(seq "$START_SLOT" "$END_SLOT"); do
  SLOT_DIR="${BASE_DIR}-${slot}"
  RUNNER_NAME="${HOST_PREFIX}-${slot}"
  if [ -f "${SLOT_DIR}/.runner" ]; then
    echo "Slot ${slot} already configured at ${SLOT_DIR}, skipping."
    continue
  fi
  REG_TOKEN="$(get_token)"
  mkdir -p "$SLOT_DIR"
  tar xzf "$TARBALL" -C "$SLOT_DIR"
  (
    cd "$SLOT_DIR"
    ./config.sh --unattended       --url "https://github.com/${REPO}"       --token "$REG_TOKEN"       --name "$RUNNER_NAME"       --labels "$LABEL"       --work "_work"       --replace
    ./svc.sh install
    ./svc.sh start
  )
  echo "Slot ${slot} (${RUNNER_NAME}) configured and started."
done
