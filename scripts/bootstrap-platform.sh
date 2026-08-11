#!/usr/bin/env bash
# Bootstrap platform components on a Kind cluster (idempotent where possible).
# Prerequisites: kind cluster from kind-config.yaml, helm, kubectl.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need kubectl
need helm

echo "==> ingress-nginx (skip if already present)"
if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml
  kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s
fi

echo "==> Argo CD (skip if already present)"
if ! kubectl get ns argocd >/dev/null 2>&1; then
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s
fi

echo "==> Vault"
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp >/dev/null
helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --version 0.34.0 \
  -f "${ROOT}/infrastructure/vault/values.yaml"

echo "==> External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --version 2.9.0 \
  -f "${ROOT}/infrastructure/external-secrets/values.yaml"

echo "==> Authentik"
if [[ ! -f "${ROOT}/infrastructure/authentik/secrets/secret-key" ]] || \
   [[ ! -f "${ROOT}/infrastructure/authentik/secrets/postgres-password" ]]; then
  mkdir -p "${ROOT}/infrastructure/authentik/secrets"
  openssl rand -hex 50 > "${ROOT}/infrastructure/authentik/secrets/secret-key"
  openssl rand -hex 32 > "${ROOT}/infrastructure/authentik/secrets/postgres-password"
  echo "Generated Authentik secrets under infrastructure/authentik/secrets/"
fi

helm repo add authentik https://charts.goauthentik.io >/dev/null 2>&1 || true
helm repo update authentik >/dev/null
AUTHENTIK_SECRET_KEY="$(tr -d '\n\r' < "${ROOT}/infrastructure/authentik/secrets/secret-key")"
POSTGRES_PASSWORD="$(tr -d '\n\r' < "${ROOT}/infrastructure/authentik/secrets/postgres-password")"
helm upgrade --install authentik authentik/authentik \
  --namespace authentik --create-namespace \
  --version 2026.5.6 \
  -f "${ROOT}/infrastructure/authentik/values.yaml" \
  --set-string authentik.secret_key="${AUTHENTIK_SECRET_KEY}" \
  --set-string authentik.postgresql.password="${POSTGRES_PASSWORD}" \
  --set-string postgresql.auth.password="${POSTGRES_PASSWORD}"

echo "==> Platform ingress"
bash "${ROOT}/scripts/apply-platform-ingress.sh"

echo "==> Workload AppProject + Applications (requires git push of this repo)"
kubectl apply -f "${ROOT}/apps/projects/workloads.yaml"
kubectl apply -f "${ROOT}/apps/workloads/"

echo "Bootstrap complete."
