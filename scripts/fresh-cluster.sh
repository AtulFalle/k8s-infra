#!/usr/bin/env bash
# Destroy and recreate Kind with a clean TODO E2E stack only.
#
# Keeps: ingress, Argo CD, Vault, ESO, Authentik, Grafana, Headlamp,
#        Argo Workflows, TODO dev/stage/prod (+ CronJobs).
# Drops: demo apps, legacy dev/stage/prod namespaces.
#
# Usage:
#   bash scripts/fresh-cluster.sh
#   KIND_LOAD=1 bash scripts/fresh-cluster.sh   # default — local image, no push
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER_NAME:-kind}"
TAG="${TAG:-0.1.2}"
KIND_LOAD="${KIND_LOAD:-1}"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
for cmd in kind kubectl helm docker; do need "$cmd"; done

echo "==> Delete cluster '${CLUSTER}' (if exists)"
kind delete cluster --name "${CLUSTER}" 2>/dev/null || true

echo "==> Create cluster"
kind create cluster --name "${CLUSTER}" --config "${ROOT}/kind-config.yaml"

echo "==> Platform (Vault, Authentik, Argo CD, ESO, ingress)"
SKIP_ARGO_WORKLOADS=1 bash "${ROOT}/scripts/bootstrap-platform.sh"

echo "==> Finalize (OIDC, Grafana, Headlamp, Workflows, CoreDNS)"
bash "${ROOT}/scripts/finalize-poc.sh"

echo "==> Deploy TODO dev/stage/prod"
KIND_LOAD="${KIND_LOAD}" TAG="${TAG}" bash "${ROOT}/scripts/deploy-todo-poc.sh"

echo "==> Register Argo CD workload applications"
kubectl apply -f "${ROOT}/apps/workloads/"

echo
echo "======== CLEAN CLUSTER READY ========"
echo "TODO:       http://todo-dev.local  http://todo-stage.local  http://todo-prod.local"
echo "Vault:      http://vault.local/ui"
echo "Grafana:    http://grafana.local  (admin/admin)"
echo "Headlamp:   http://headlamp.local"
echo "Workflows:  http://workflows.local"
echo "Argo CD:    http://argocd.local"
echo "Authentik:  http://authentik.local"
echo
echo "Hosts (add to C:\\Windows\\System32\\drivers\\etc\\hosts):"
echo "  127.0.0.1 todo-dev.local todo-stage.local todo-prod.local"
echo "  127.0.0.1 authentik.local argocd.local vault.local grafana.local"
echo "  127.0.0.1 headlamp.local workflows.local"
echo
echo "Authentik: akadmin / $(tr -d '\n\r' < "${ROOT}/infrastructure/authentik/secrets/bootstrap-password")"
echo "====================================="
