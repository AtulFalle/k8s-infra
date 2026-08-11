#!/usr/bin/env bash
# Build TODO, push to Docker Hub, ensure pull secrets + Vault, deploy all envs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${TAG:-0.1.0}"
IMAGE="atulfalle1815/todo:${TAG}"

echo "==> Building ${IMAGE}"
docker build -t "${IMAGE}" -t atulfalle1815/todo:dev "${ROOT}/workloads/todo"

echo "==> Pushing ${IMAGE}"
docker push "${IMAGE}"
docker push atulfalle1815/todo:dev

echo "==> Docker Hub pull secrets"
bash "${ROOT}/scripts/create-dockerhub-pull-secret.sh"

echo "==> Vault TODO secrets/roles"
bash "${ROOT}/scripts/bootstrap-vault-todo.sh"

for env in dev stage prod; do
  ns="todo-${env}"
  echo "==> Helm upgrade todo in ${ns}"
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install todo "${ROOT}/charts/todo" \
    --namespace "${ns}" \
    -f "${ROOT}/envs/todo/${env}/values.yaml" \
    --set image.tag="${TAG}" \
    --set config.APP_VERSION="${TAG}"
done

echo "==> Waiting for ExternalSecrets + rollout"
for env in dev stage prod; do
  ns="todo-${env}"
  kubectl -n "$ns" wait --for=condition=Ready externalsecret/todo-secrets --timeout=120s || \
    kubectl -n "$ns" get externalsecret,secretstore,secret -o wide
  kubectl -n "$ns" rollout status deploy/todo --timeout=180s
done

echo "==> Smoke"
for h in todo-dev.local todo-stage.local todo-prod.local; do
  echo -n "$h -> "
  curl -s -H "Host: $h" http://127.0.0.1/api/meta
  echo
done
