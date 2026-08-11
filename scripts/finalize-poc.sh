#!/usr/bin/env bash
# Finalize POC: CoreDNS, Authentik OIDC, Grafana, Headlamp, Argo Workflows.
# Does NOT helm-upgrade TODO while Argo owns it — bump envs/todo/*/values.yaml and sync Argo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AK_SECRETS="${ROOT}/infrastructure/authentik/secrets"

need_file() {
  [[ -f "$1" ]] || { echo "missing $1"; exit 1; }
}

ensure_oidc_client() {
  local id_file=$1 secret_file=$2 id_prefix=$3
  if [[ ! -f "${id_file}" ]]; then
    echo "${id_prefix}-$(openssl rand -hex 4)" > "${id_file}"
    echo "Generated ${id_file}"
  fi
  if [[ ! -f "${secret_file}" ]]; then
    openssl rand -hex 32 > "${secret_file}"
    echo "Generated ${secret_file}"
  fi
}

mkdir -p "${AK_SECRETS}"
ensure_oidc_client "${AK_SECRETS}/headlamp-client-id" "${AK_SECRETS}/headlamp-client-secret" "headlamp"
ensure_oidc_client "${AK_SECRETS}/workflows-client-id" "${AK_SECRETS}/workflows-client-secret" "workflows"

for f in bootstrap-email bootstrap-password argocd-client-id argocd-client-secret \
         vault-client-id vault-client-secret headlamp-client-id headlamp-client-secret \
         workflows-client-id workflows-client-secret secret-key postgres-password; do
  need_file "${AK_SECRETS}/${f}"
done

ARGOCD_CID="$(tr -d '\n\r' < "${AK_SECRETS}/argocd-client-id")"
ARGOCD_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/argocd-client-secret")"
VAULT_CID="$(tr -d '\n\r' < "${AK_SECRETS}/vault-client-id")"
VAULT_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/vault-client-secret")"
HEADLAMP_CID="$(tr -d '\n\r' < "${AK_SECRETS}/headlamp-client-id")"
HEADLAMP_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/headlamp-client-secret")"
WORKFLOWS_CID="$(tr -d '\n\r' < "${AK_SECRETS}/workflows-client-id")"
WORKFLOWS_CSEC="$(tr -d '\n\r' < "${AK_SECRETS}/workflows-client-secret")"
BOOT_EMAIL="$(tr -d '\n\r' < "${AK_SECRETS}/bootstrap-email")"
BOOT_PASS="$(tr -d '\n\r' < "${AK_SECRETS}/bootstrap-password")"
AK_KEY="$(tr -d '\n\r' < "${AK_SECRETS}/secret-key")"
PG_PASS="$(tr -d '\n\r' < "${AK_SECRETS}/postgres-password")"

echo "==> CoreDNS rewrites for *.local"
bash "${ROOT}/scripts/patch-coredns-local.sh"

echo "==> Authentik bootstrap + OIDC client secrets"
kubectl create namespace authentik --dry-run=client -o yaml | kubectl apply -f -
kubectl -n authentik create secret generic authentik-bootstrap \
  --from-literal=email="${BOOT_EMAIL}" \
  --from-literal=password="${BOOT_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -
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

echo "==> Authentik blueprints ConfigMap (normalize LF)"
BP_TMP="$(mktemp)"
sed $'s/\r$//' "${ROOT}/infrastructure/authentik/blueprints/poc-oidc-apps.yaml" > "${BP_TMP}"
kubectl -n authentik create configmap authentik-blueprints \
  --from-file=poc-oidc-apps.yaml="${BP_TMP}" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "${BP_TMP}"

echo "==> Helm upgrade authentik"
helm upgrade --install authentik authentik/authentik \
  --namespace authentik \
  --version 2026.5.6 \
  -f "${ROOT}/infrastructure/authentik/values.yaml" \
  --set-string authentik.secret_key="${AK_KEY}" \
  --set-string authentik.postgresql.password="${PG_PASS}" \
  --set-string postgresql.auth.password="${PG_PASS}"

kubectl -n authentik rollout status deploy/authentik-server --timeout=300s
kubectl -n authentik rollout status deploy/authentik-worker --timeout=300s
kubectl apply -f "${ROOT}/infrastructure/authentik/ingress.yaml"

echo "==> Apply Authentik blueprints + link akadmin to groups"
kubectl -n authentik rollout restart deploy/authentik-worker
kubectl -n authentik rollout status deploy/authentik-worker --timeout=180s
kubectl exec -n authentik deploy/authentik-worker -- \
  ak apply_blueprint /blueprints/custom/poc-oidc-apps.yaml 2>/dev/null \
  || kubectl exec -n authentik deploy/authentik-worker -- \
       ak apply_blueprint /blueprints/poc-oidc-apps.yaml 2>/dev/null \
  || echo "(blueprint apply will also run from mounted ConfigMap on worker start)"

kubectl exec -n authentik deploy/authentik-worker -- ak shell -c '
from authentik.core.models import User, Group
u = User.objects.filter(username="akadmin").first()
for name in ["Argo CD Admins", "Argo CD Viewers", "Vault Admins", "Platform Admins"]:
    g, _ = Group.objects.get_or_create(name=name)
    if u:
        g.users.add(u)
print("akadmin groups ready" if u else "akadmin missing")
' >/dev/null

echo "==> Wait for OIDC discovery"
for i in $(seq 1 36); do
  if curl -sf -H 'Host: authentik.local' \
      http://127.0.0.1/application/o/argocd/.well-known/openid-configuration >/dev/null \
     && curl -sf -H 'Host: authentik.local' \
      http://127.0.0.1/application/o/vault/.well-known/openid-configuration >/dev/null \
     && curl -sf -H 'Host: authentik.local' \
      http://127.0.0.1/application/o/headlamp/.well-known/openid-configuration >/dev/null \
     && curl -sf -H 'Host: authentik.local' \
      http://127.0.0.1/application/o/workflows/.well-known/openid-configuration >/dev/null; then
    echo "OIDC issuers ready"
    break
  fi
  echo "waiting for blueprints... ($i)"
  sleep 5
done

echo "==> Configure Argo CD Dex → Authentik"
kubectl -n argocd patch secret argocd-secret --type merge -p \
  "{\"stringData\":{\"dex.authentik.clientSecret\":\"${ARGOCD_CSEC}\"}}"

export ARGOCD_CID
python <<'PY'
import json, os, subprocess, textwrap
cid = os.environ["ARGOCD_CID"]
cm = json.loads(subprocess.check_output(
    ["kubectl", "get", "cm", "argocd-cm", "-n", "argocd", "-o", "json"], text=True))
data = cm.setdefault("data", {})
data["url"] = "http://argocd.local"
data["dex.config"] = textwrap.dedent(f"""\
    connectors:
    - type: oidc
      id: authentik
      name: authentik
      config:
        issuer: http://authentik.local/application/o/argocd/
        clientID: {cid}
        clientSecret: $dex.authentik.clientSecret
        insecureEnableGroups: true
        scopes:
          - openid
          - profile
          - email
          - groups
""")
subprocess.run(["kubectl", "apply", "-f", "-"], input=json.dumps(cm), text=True, check=True)

rbac = json.loads(subprocess.check_output(
    ["kubectl", "get", "cm", "argocd-rbac-cm", "-n", "argocd", "-o", "json"], text=True))
rbac.setdefault("data", {})["policy.csv"] = (
    "g, Argo CD Admins, role:admin\n"
    "g, Argo CD Viewers, role:readonly\n"
)
subprocess.run(["kubectl", "apply", "-f", "-"], input=json.dumps(rbac), text=True, check=True)
print("Argo CD cm/rbac updated")
PY

kubectl apply -f "${ROOT}/infrastructure/argocd/cmd-params-patch.yaml"
kubectl apply -f "${ROOT}/infrastructure/argocd/ingress.yaml"
kubectl -n argocd rollout restart deploy/argocd-server deploy/argocd-dex-server
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=180s

echo "==> Configure Vault OIDC"
kubectl exec -n vault vault-0 -- vault auth enable oidc 2>/dev/null || true
kubectl exec -n vault vault-0 -- vault write auth/oidc/config \
  oidc_discovery_url="http://authentik.local/application/o/vault/" \
  oidc_client_id="${VAULT_CID}" \
  oidc_client_secret="${VAULT_CSEC}" \
  default_role="default"

kubectl exec -n vault vault-0 -- vault write auth/oidc/role/default \
  bound_audiences="${VAULT_CID}" \
  allowed_redirect_uris="http://vault.local/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://vault.local/oidc/callback" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  user_claim="email" \
  groups_claim="groups" \
  oidc_scopes="openid,profile,email,groups" \
  policies="default" \
  ttl=1h

kubectl exec -n vault vault-0 -- sh -c 'cat > /tmp/vault-admins.hcl <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
vault policy write vault-admins /tmp/vault-admins.hcl'

OIDC_ACCESSOR=$(kubectl exec -n vault vault-0 -- vault auth list -format=json \
  | python -c "import sys,json; print(json.load(sys.stdin)['oidc/']['accessor'])")
kubectl exec -n vault vault-0 -- vault write identity/group name="Vault Admins" \
  type="external" policies="vault-admins" >/dev/null 2>&1 || true
GROUP_ID=$(kubectl exec -n vault vault-0 -- vault read -field=id 'identity/group/name/Vault Admins' 2>/dev/null || true)
if [[ -n "${GROUP_ID}" ]]; then
  kubectl exec -n vault vault-0 -- vault write identity/group-alias \
    name="Vault Admins" mount_accessor="${OIDC_ACCESSOR}" canonical_id="${GROUP_ID}" >/dev/null 2>&1 || true
fi
kubectl apply -f "${ROOT}/infrastructure/vault/ingress.yaml"

echo "==> Install Grafana / Prometheus (incl. job failure rules)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version 72.6.2 \
  -f "${ROOT}/infrastructure/monitoring/values.yaml"
kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=300s || true

echo "==> Headlamp + Argo Workflows (jobs platform)"
bash "${ROOT}/scripts/bootstrap-jobs-platform.sh"

echo
echo "======== POC LOGIN ========="
echo "Authentik:  http://authentik.local"
echo "  user: akadmin"
echo "  pass: (cat infrastructure/authentik/secrets/bootstrap-password)"
echo "Argo CD:    http://argocd.local       → LOG IN VIA authentik"
echo "Vault:      http://vault.local/ui     → OIDC (or token root)"
echo "Grafana:    http://grafana.local      → admin / admin"
echo "Headlamp:   http://headlamp.local     → LOG IN VIA authentik"
echo "Workflows:  http://workflows.local    → LOG IN VIA authentik"
echo "TODO:       http://todo-dev.local"
echo
echo "Hosts:"
echo "  127.0.0.1 authentik.local argocd.local vault.local grafana.local"
echo "  127.0.0.1 headlamp.local workflows.local"
echo "  127.0.0.1 todo-dev.local todo-stage.local todo-prod.local"
echo
echo "Jobs POC: CronJob runs app image CLI (job cleanup/digest)."
echo "  See docs/JOBS_ARCHITECTURE.md"
echo "TODO GitOps: commit/push envs+chart (tag 0.1.2), then Argo sync."
echo "============================"
