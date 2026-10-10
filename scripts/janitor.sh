#!/usr/bin/env bash
# Garbage-collect stale preview environments.
#
# Deletes every namespace labelled preview=true whose PR is no longer open,
# or which is older than MAX_AGE_DAYS. Catches previews orphaned by missed
# `closed` events, cancelled runs, or manual deploys.
#
# env:
#   GH_TOKEN       (required in CI) token for `gh pr list`
#   GH_REPO        (optional) owner/repo; defaults to the current git remote
#   MAX_AGE_DAYS   (optional) default 7
#   DRY_RUN=1      (optional) print what would be deleted, delete nothing
set -euo pipefail

MAX_AGE_DAYS="${MAX_AGE_DAYS:-7}"
DRY_RUN="${DRY_RUN:-0}"
[[ "${MAX_AGE_DAYS}" =~ ^[0-9]+$ ]] || { echo "[janitor] ERROR: MAX_AGE_DAYS must be digits" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

to_epoch() {
  # GNU date (Linux/CI) first, then BSD date (macOS).
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s
}

# Fail closed: if we can't list open PRs, delete nothing.
if ! OPEN_PRS="$(gh pr list --state open --limit 1000 --json number --jq '.[].number')"; then
  echo "[janitor] ERROR: could not list open PRs — aborting without deleting anything." >&2
  exit 1
fi
echo "[janitor] Open PRs: ${OPEN_PRS//$'\n'/ }"

NOW="$(date -u +%s)"
MAX_AGE_SECS=$(( MAX_AGE_DAYS * 86400 ))
DELETED=0
KEPT=0

NAMESPACES="$(kubectl get namespaces -l preview=true \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.pr}{" "}{.metadata.creationTimestamp}{"\n"}{end}')"

if [[ -z "${NAMESPACES}" ]]; then
  echo "[janitor] No preview namespaces found."
  exit 0
fi

while read -r NS PR CREATED; do
  [[ -n "${NS}" ]] || continue
  if [[ ! "${PR}" =~ ^[0-9]+$ ]]; then
    echo "[janitor] WARN: ${NS} has no valid pr label — skipping."
    continue
  fi
  if [[ "${NS}" != "pr-${PR}" ]]; then
    echo "[janitor] WARN: ${NS} does not match pr label ${PR} — skipping."
    continue
  fi

  AGE_SECS=$(( NOW - $(to_epoch "${CREATED}") ))
  AGE_DAYS=$(( AGE_SECS / 86400 ))
  REASON=""
  if ! grep -qx "${PR}" <<< "${OPEN_PRS}"; then
    REASON="PR #${PR} is not open"
  elif (( AGE_SECS > MAX_AGE_SECS )); then
    REASON="older than ${MAX_AGE_DAYS}d (${AGE_DAYS}d)"
  fi

  if [[ -z "${REASON}" ]]; then
    echo "[janitor] keep   ${NS} (PR #${PR} open, ${AGE_DAYS}d old)"
    KEPT=$(( KEPT + 1 ))
    continue
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[janitor] DRY_RUN would delete ${NS}: ${REASON}"
  else
    echo "[janitor] delete ${NS}: ${REASON}"
    bash "${SCRIPT_DIR}/preview-down.sh" "${PR}"
  fi
  DELETED=$(( DELETED + 1 ))
done <<< "${NAMESPACES}"

echo "[janitor] ✓ Done. kept=${KEPT} deleted=${DELETED}$([[ "${DRY_RUN}" == "1" ]] && echo ' (dry run)')"
