#!/usr/bin/env bash
# Build TODO, load/push image, seed Vault, deploy dev/stage/prod via Helm.
# Use KIND_LOAD=1 on fresh Kind (no Docker Hub push required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${TAG:-0.1.2}"
IMAGE="atulfalle1815/todo:${TAG}"
KIND_LOAD="${KIND_LOAD:-0}"

echo "==> Building ${IMAGE}"
docker build -t "${IMAGE}" "${ROOT}/workloads/todo"

if [[ "${KIND_LOAD}" == "1" ]]; then
  echo "==> Loading image into Kind (local)"
  kind load docker-image "${IMAGE}" --name kind
else
  echo "==> Pushing ${IMAGE}"
  docker push "${IMAGE}"
fi

echo "==> Docker Hub pull secrets (todo namespaces)"
if [[ "${KIND_LOAD}" != "1" ]]; then
  bash "${ROOT}/scripts/create-dockerhub-pull-secret.sh"
else
  for ns in todo-dev todo-stage todo-prod; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  done
fi

echo "==> Vault TODO secrets/roles"
bash "${ROOT}/scripts/bootstrap-vault-todo.sh"

PULL_POLICY="Always"
[[ "${KIND_LOAD}" == "1" ]] && PULL_POLICY="IfNotPresent"

for env in dev stage prod; do
  ns="todo-${env}"
  echo "==> Helm upgrade todo in ${ns}"
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install todo "${ROOT}/charts/todo" \
    --namespace "${ns}" \
    -f "${ROOT}/envs/todo/${env}/values.yaml" \
    --set image.tag="${TAG}" \
    --set image.pullPolicy="${PULL_POLICY}" \
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
  curl -s -H "Host: $h" http://127.0.0.1/api/meta || echo "(no response)"
  echo
done

echo "TODO deploy complete."
