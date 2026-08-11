#!/usr/bin/env bash
# Idempotent Vault seed + K8s auth + roles for TODO.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Wait for Vault"
kubectl -n vault wait --for=condition=ready pod/vault-0 --timeout=120s

echo "==> Enable Kubernetes auth (if needed)"
kubectl exec -n vault vault-0 -- vault auth enable kubernetes 2>/dev/null || true
kubectl exec -n vault vault-0 -- sh -c '
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  disable_iss_validation=true
'

for env in dev stage prod; do
  banner="Hello from Vault (${env}) — TODO secrets path OK"
  kubectl exec -n vault vault-0 -- vault kv put "secret/${env}/todo" \
    APP_BANNER="${banner}" \
    DEMO_API_KEY="todo-${env}-demo-key" \
    >/dev/null
  echo "secret/${env}/todo upserted"
done

for env in dev stage prod; do
  kubectl exec -i -n vault vault-0 -- vault policy write "todo-${env}" - \
    <"${ROOT}/infrastructure/vault/policies/todo-${env}.hcl"
  kubectl exec -n vault vault-0 -- vault write "auth/kubernetes/role/todo-${env}" \
    bound_service_account_names=vault-todo \
    bound_service_account_namespaces="todo-${env}" \
    policies="todo-${env}" \
    ttl=1h >/dev/null
  echo "role todo-${env} upserted"
done

echo "Vault TODO bootstrap complete."
