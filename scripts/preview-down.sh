#!/usr/bin/env bash
# Tear down the preview environment for a pull request. Safe to re-run.
#
#   usage: scripts/preview-down.sh <pr-number>
set -euo pipefail

usage() { echo "usage: $0 <pr-number>" >&2; exit 2; }

PR="${1:-}"
[[ -n "${PR}" ]] || usage
[[ "${PR}" =~ ^[0-9]+$ ]] || { echo "[preview-down] ERROR: pr must be digits, got '${PR}'" >&2; exit 2; }

NAMESPACE="pr-${PR}"
RELEASE="preview-${PR}"

if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "[preview-down] Namespace ${NAMESPACE} not found — nothing to do."
  exit 0
fi

if helm status "${RELEASE}" --namespace "${NAMESPACE}" &>/dev/null; then
  echo "[preview-down] helm uninstall ${RELEASE}"
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" --wait --timeout 3m
else
  echo "[preview-down] Release ${RELEASE} not found — skipping helm uninstall."
fi

echo "[preview-down] Deleting namespace ${NAMESPACE}"
kubectl delete namespace "${NAMESPACE}" --ignore-not-found --wait=true --timeout=5m

echo "[preview-down] ✓ Preview for PR #${PR} destroyed."
