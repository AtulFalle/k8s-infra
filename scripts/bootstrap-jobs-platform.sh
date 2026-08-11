#!/usr/bin/env bash
# Install Headlamp + Argo Workflows and apply TODO workflow reference.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AK_SECRETS="${ROOT}/infrastructure/authentik/secrets"

HEADLAMP_CID="$(tr -d '\n\r' < "${AK_SECRETS}/headlamp-client-id")"
HEADLAMP_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/headlamp-client-secret")"
WORKFLOWS_CID="$(tr -d '\n\r' < "${AK_SECRETS}/workflows-client-id")"
WORKFLOWS_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/workflows-client-secret")"

echo "==> Headlamp"
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null 2>&1 || true
helm repo update headlamp >/dev/null
helm upgrade --install headlamp headlamp/headlamp \
  --namespace headlamp --create-namespace \
  --version 0.30.0 \
  -f "${ROOT}/infrastructure/headlamp/values.yaml" \
  --set-string config.oidc.clientID="${HEADLAMP_CID}" \
  --set-string config.oidc.clientSecret="${HEADLAMP_CSEC}" \
  --set-string config.oidc.issuerURL="http://authentik.local/application/o/headlamp/" \
  --set-string config.oidc.scopes="openid,profile,email"
kubectl -n headlamp rollout status deploy/headlamp --timeout=180s || \
  kubectl -n headlamp rollout status deploy/headlamp-headlamp --timeout=180s || true

echo "==> Argo Workflows"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argo create secret generic argo-workflows-sso \
  --from-literal=client-id="${WORKFLOWS_CID}" \
  --from-literal=client-secret="${WORKFLOWS_CSEC}" \
  --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argo-workflows argo/argo-workflows \
  --namespace argo \
  --version 0.45.6 \
  -f "${ROOT}/infrastructure/argo-workflows/values.yaml"
kubectl -n argo rollout status deploy/argo-workflows-server --timeout=300s || true
kubectl -n argo rollout status deploy/argo-workflows-workflow-controller --timeout=300s || true

echo "==> TODO digest pipeline (todo-dev)"
kubectl create namespace todo-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${ROOT}/workflows/todo/digest-pipeline.yaml"

echo "Jobs platform ready."
echo "  Headlamp:  http://headlamp.local"
echo "  Workflows: http://workflows.local"
