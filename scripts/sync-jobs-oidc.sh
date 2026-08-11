#!/usr/bin/env bash
# Register Headlamp + Argo Workflows OIDC apps in Authentik (after bootstrap-jobs-platform.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AK_SECRETS="${ROOT}/infrastructure/authentik/secrets"

for f in headlamp-client-id headlamp-client-secret workflows-client-id workflows-client-secret \
         secret-key postgres-password; do
  [[ -f "${AK_SECRETS}/${f}" ]] || { echo "missing ${AK_SECRETS}/${f} — run bootstrap-jobs-platform.sh first"; exit 1; }
done

HEADLAMP_CID="$(tr -d '\n\r' < "${AK_SECRETS}/headlamp-client-id")"
HEADLAMP_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/headlamp-client-secret")"
WORKFLOWS_CID="$(tr -d '\n\r' < "${AK_SECRETS}/workflows-client-id")"
WORKFLOWS_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/workflows-client-secret")"
ARGOCD_CID="$(tr -d '\n\r' < "${AK_SECRETS}/argocd-client-id")"
ARGOCD_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/argocd-client-secret")"
VAULT_CID="$(tr -d '\n\r' < "${AK_SECRETS}/vault-client-id")"
VAULT_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/vault-client-secret")"
AK_KEY="$(tr -d '\n\r' < "${AK_SECRETS}/secret-key")"
PG_PASS="$(tr -d '\n\r' < "${AK_SECRETS}/postgres-password")"

echo "==> Patch Authentik OIDC client secret (incl. Headlamp + Workflows)"
kubectl -n authentik create secret generic authentik-oidc-clients \
  --from-literal=argocd-client-id="${ARGOCD_CID}" \
  --from-literal=argocd-client-secret="${ARGOCD_CSEC}" \
  --from-literal=vault-client-id="${VAULT_CID}" \
  --from-literal=vault-client-secret="${VAULT_CSEC}" \
  --from-literal=headlamp-client-id="${HEADLAMP_CID}" \
  --from-literal=headlamp-client-secret="${HEADLAMP_CSEC}" \
  --from-literal=workflows-client-id="${WORKFLOWS_CID}" \
  --from-literal=workflows-client-secret="${WORKFLOWS_CSEC}" \
  --dry-run=client -o yaml | kubectl apply -f -

BP_TMP="$(mktemp)"
sed $'s/\r$//' "${ROOT}/infrastructure/authentik/blueprints/poc-oidc-apps.yaml" > "${BP_TMP}"
kubectl -n authentik create configmap authentik-blueprints \
  --from-file=poc-oidc-apps.yaml="${BP_TMP}" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "${BP_TMP}"

echo "==> Helm upgrade authentik (reload blueprint env)"
helm upgrade authentik authentik/authentik \
  --namespace authentik \
  --version 2026.5.6 \
  -f "${ROOT}/infrastructure/authentik/values.yaml" \
  --set-string authentik.secret_key="${AK_KEY}" \
  --set-string authentik.postgresql.password="${PG_PASS}" \
  --set-string postgresql.auth.password="${PG_PASS}"

kubectl -n authentik rollout restart deploy/authentik-worker
kubectl -n authentik rollout status deploy/authentik-worker --timeout=180s

# Blueprint auto-applies from mounted ConfigMap on worker start (avoid Windows Git Bash path mangling).

kubectl exec -n authentik deploy/authentik-worker -- ak shell -c '
from authentik.core.models import User, Group
u = User.objects.filter(username="akadmin").first()
for name in ["Platform Admins", "Argo CD Admins", "Vault Admins"]:
    g, _ = Group.objects.get_or_create(name=name)
    if u:
        g.users.add(u)
print("groups linked")
'

echo "==> Wait for Headlamp + Workflows OIDC discovery"
for i in $(seq 1 24); do
  if curl -sf -H 'Host: authentik.local' \
      http://127.0.0.1/application/o/headlamp/.well-known/openid-configuration >/dev/null \
     && curl -sf -H 'Host: authentik.local' \
      http://127.0.0.1/application/o/workflows/.well-known/openid-configuration >/dev/null; then
    echo "OIDC ready"
    break
  fi
  echo "waiting... ($i)"
  sleep 5
done

echo "==> Restart Argo Workflows server"
kubectl -n argo rollout restart deploy/argo-workflows-server
kubectl -n argo rollout status deploy/argo-workflows-server --timeout=180s

echo "==> Apply digest pipeline"
kubectl apply -f "${ROOT}/workflows/todo/digest-pipeline.yaml"

echo "Done. http://headlamp.local and http://workflows.local"
