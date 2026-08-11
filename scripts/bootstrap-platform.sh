#!/usr/bin/env bash
# Bootstrap platform for TODO E2E POC (no demo workloads).
# Prerequisites: kind cluster from kind-config.yaml, helm, kubectl.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need kubectl
need helm

echo "==> Authentik secret files"
bash "${ROOT}/scripts/init-authentik-secrets.sh"

echo "==> ingress-nginx"
if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml
  kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s
fi

echo "==> Argo CD"
if ! kubectl get ns argocd >/dev/null 2>&1; then
  kubectl create namespace argocd
  kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
fi

echo "==> Vault"
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp >/dev/null
helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --version 0.34.0 \
  -f "${ROOT}/infrastructure/vault/values.yaml"
kubectl -n vault wait --for=condition=ready pod/vault-0 --timeout=300s

echo "==> External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --version 2.9.0 \
  -f "${ROOT}/infrastructure/external-secrets/values.yaml"
kubectl -n external-secrets wait --for=condition=available deployment/external-secrets --timeout=180s

echo "==> Authentik"
AUTHENTIK_SECRET_KEY="$(tr -d '\n\r' < "${ROOT}/infrastructure/authentik/secrets/secret-key")"
POSTGRES_PASSWORD="$(tr -d '\n\r' < "${ROOT}/infrastructure/authentik/secrets/postgres-password")"
helm repo add authentik https://charts.goauthentik.io >/dev/null 2>&1 || true
helm repo update authentik >/dev/null
helm upgrade --install authentik authentik/authentik \
  --namespace authentik --create-namespace \
  --version 2026.5.6 \
  -f "${ROOT}/infrastructure/authentik/values.yaml" \
  --set-string authentik.secret_key="${AUTHENTIK_SECRET_KEY}" \
  --set-string authentik.postgresql.password="${POSTGRES_PASSWORD}" \
  --set-string postgresql.auth.password="${POSTGRES_PASSWORD}"

echo "==> Platform ingress (Authentik, Argo CD, Vault)"
bash "${ROOT}/scripts/apply-platform-ingress.sh"

echo "==> Argo CD AppProject + TODO Applications"
kubectl apply -f "${ROOT}/apps/projects/workloads.yaml"
if [[ "${SKIP_ARGO_WORKLOADS:-0}" != "1" ]]; then
  kubectl apply -f "${ROOT}/apps/workloads/todo-dev.yaml"
  kubectl apply -f "${ROOT}/apps/workloads/todo-stage.yaml"
  kubectl apply -f "${ROOT}/apps/workloads/todo-prod.yaml"
else
  echo "(skipped TODO Applications — use helm for local bootstrap, then: kubectl apply -f apps/workloads/)"
fi

echo "Platform bootstrap complete (workloads: helm or Argo sync next)."
