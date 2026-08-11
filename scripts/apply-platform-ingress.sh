#!/usr/bin/env bash
# Apply platform Ingress resources and Argo CD settings required for host-based access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Patching Argo CD for ingress (server.insecure=true)"
kubectl apply -f "${ROOT}/infrastructure/argocd/cmd-params-patch.yaml"
kubectl -n argocd rollout restart deployment/argocd-server
kubectl -n argocd rollout status deployment/argocd-server --timeout=120s

echo "==> Prefer ClusterIP for argocd-server (ingress is the entrypoint)"
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"ClusterIP"}}' || true

echo "==> Applying platform Ingresses"
kubectl apply -f "${ROOT}/infrastructure/authentik/ingress.yaml"
kubectl apply -f "${ROOT}/infrastructure/argocd/ingress.yaml"
kubectl apply -f "${ROOT}/infrastructure/vault/ingress.yaml"

echo "==> Ingress status"
kubectl get ingress -A

cat <<'EOF'

Done. Add these hosts (see README) then open:
  http://authentik.local
  http://argocd.local
  http://vault.local
EOF
