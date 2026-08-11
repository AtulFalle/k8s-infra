#!/usr/bin/env bash
# Generate Authentik + OIDC client secret files for a fresh POC (idempotent).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${ROOT}/infrastructure/authentik/secrets"
mkdir -p "${DIR}"

gen() {
  local path=$1 cmd=$2
  if [[ ! -f "${path}" ]]; then
    eval "${cmd}" > "${path}"
    echo "Generated ${path}"
  fi
}

gen "${DIR}/secret-key" "openssl rand -hex 50"
gen "${DIR}/postgres-password" "openssl rand -hex 32"
gen "${DIR}/bootstrap-email" "echo akadmin@local"
gen "${DIR}/bootstrap-password" "openssl rand -base64 18"
gen "${DIR}/argocd-client-id" "echo argocd-$(openssl rand -hex 4)"
gen "${DIR}/argocd-client-secret" "openssl rand -hex 32"
gen "${DIR}/vault-client-id" "echo vault-$(openssl rand -hex 4)"
gen "${DIR}/vault-client-secret" "openssl rand -hex 32"
gen "${DIR}/headlamp-client-id" "echo headlamp-$(openssl rand -hex 4)"
gen "${DIR}/headlamp-client-secret" "openssl rand -hex 32"
gen "${DIR}/workflows-client-id" "echo workflows-$(openssl rand -hex 4)"
gen "${DIR}/workflows-client-secret" "openssl rand -hex 32"

echo "Authentik secrets ready under ${DIR}/"
