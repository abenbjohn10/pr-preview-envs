#!/usr/bin/env bash
# One-time (idempotent) cluster add-ons for preview environments.
# Required env: CERT_MANAGER_ROLE_ARN, HOSTED_ZONE_ID, ACME_EMAIL, PREVIEW_DOMAIN
set -euo pipefail
cd "$(dirname "$0")"

: "${CERT_MANAGER_ROLE_ARN:?set CERT_MANAGER_ROLE_ARN}"
: "${HOSTED_ZONE_ID:?set HOSTED_ZONE_ID}"
: "${ACME_EMAIL:?set ACME_EMAIL}"
: "${PREVIEW_DOMAIN:?set PREVIEW_DOMAIN (e.g. example.com)}"

helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add emberstack https://emberstack.github.io/helm-charts --force-update
helm repo update jetstack emberstack

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  -f cert-manager-values.yaml \
  --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${CERT_MANAGER_ROLE_ARN}" \
  --wait --timeout 5m

helm upgrade --install reflector emberstack/reflector \
  --namespace kube-system -f reflector-values.yaml --wait --timeout 5m

kubectl apply -f rbac.yaml

render() {
  sed -e "s|REPLACE_ME_HOSTED_ZONE_ID|${HOSTED_ZONE_ID}|g" \
      -e "s|REPLACE_ME_EMAIL|${ACME_EMAIL}|g" \
      -e "s|REPLACE_ME_example.com|${PREVIEW_DOMAIN}|g" "$1"
}

kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s
render clusterissuers.yaml | kubectl apply -f -
render preview-system.yaml | kubectl apply -f -

echo "Done. Watch the wildcard cert: kubectl -n preview-system get certificate preview-wildcard -w"
