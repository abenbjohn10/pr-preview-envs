#!/usr/bin/env bash
# Deploy (or redeploy) the preview environment for a pull request.
#
#   usage: scripts/preview-up.sh <pr-number> <image-tag>
#
# env:
#   ECR_REGISTRY     (required) registry host, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com
#   PREVIEW_DOMAIN   (required) base domain; host = pr-<N>.preview.<PREVIEW_DOMAIN>
#   GIT_SHA          (optional) commit sha shown in the app banner (default: derived from tag)
#   PREVIEW_HOST     (optional) override the full hostname (e.g. pr-1.localtest.me for kind)
#   EXTRA_HELM_ARGS  (optional) extra args appended to helm upgrade (later --set wins)
set -euo pipefail

usage() { echo "usage: $0 <pr-number> <image-tag>" >&2; exit 2; }

PR="${1:-}"
TAG="${2:-}"
[[ -n "${PR}" && -n "${TAG}" ]] || usage
[[ "${PR}" =~ ^[0-9]+$ ]] || { echo "[preview-up] ERROR: pr must be digits, got '${PR}'" >&2; exit 2; }
[[ "${TAG}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { echo "[preview-up] ERROR: invalid image tag '${TAG}'" >&2; exit 2; }

ECR_REGISTRY="${ECR_REGISTRY:?ECR_REGISTRY env var required}"
PREVIEW_DOMAIN="${PREVIEW_DOMAIN:?PREVIEW_DOMAIN env var required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="${SCRIPT_DIR}/../charts/preview-app"
NAMESPACE="pr-${PR}"
RELEASE="preview-${PR}"
HOST="${PREVIEW_HOST:-pr-${PR}.preview.${PREVIEW_DOMAIN}}"

# Tag format is pr-<N>-<shortsha>; fall back to the tag itself.
DEFAULT_SHA="${TAG##*-}"
GIT_SHA="${GIT_SHA:-${DEFAULT_SHA}}"

EXTRA_ARGS=()
if [[ -n "${EXTRA_HELM_ARGS:-}" ]]; then
  read -r -a EXTRA_ARGS <<< "${EXTRA_HELM_ARGS}"
fi

SCHEME="https"
if [[ "${EXTRA_HELM_ARGS:-}" == *"ingress.tls.enabled=false"* ]]; then
  SCHEME="http"
fi

echo "[preview-up] PR #${PR} → namespace ${NAMESPACE}, release ${RELEASE}, tag ${TAG}"

# Namespace: create if missing, (re)apply labels — idempotent.
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${NAMESPACE}" preview=true "pr=${PR}" --overwrite

echo "[preview-up] helm upgrade --install ${RELEASE} (timeout 5m)"
helm upgrade --install "${RELEASE}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  --set "prNumber=${PR}" \
  --set "gitSha=${GIT_SHA}" \
  --set "imageRegistry=${ECR_REGISTRY}" \
  --set "backend.image.tag=${TAG}" \
  --set "frontend.image.tag=${TAG}" \
  --set "ingress.host=${HOST}" \
  --wait \
  --timeout 5m \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

URL="${SCHEME}://${HOST}"
echo "[preview-up] ✓ Preview ready: ${URL}"

# Expose the URL to GitHub Actions when running in CI.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "url=${URL}" >> "${GITHUB_OUTPUT}"
fi
