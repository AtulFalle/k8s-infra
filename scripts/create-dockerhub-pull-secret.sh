#!/usr/bin/env bash
# Create dockerhub imagePullSecret in todo namespaces from local Docker Desktop login.
set -euo pipefail

USER_NAME="${DOCKERHUB_USERNAME:-atulfalle1815}"
SERVER="https://index.docker.io/v1/"

if ! command -v docker-credential-desktop >/dev/null 2>&1; then
  echo "docker-credential-desktop not found; set DOCKERHUB_TOKEN and re-run"
  exit 1
fi

CREDS_JSON=$(printf '%s' "$SERVER" | docker-credential-desktop get)
PASS=$(python -c "import sys,json; print(json.load(sys.stdin)['Secret'])" <<<"$CREDS_JSON")
USER_FROM_HELPER=$(python -c "import sys,json; print(json.load(sys.stdin)['Username'])" <<<"$CREDS_JSON")
USER_NAME="${USER_FROM_HELPER:-$USER_NAME}"

AUTH=$(printf '%s:%s' "$USER_NAME" "$PASS" | base64 | tr -d '\n')
DOCKERCFG=$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
  "$SERVER" "$USER_NAME" "$PASS" "$AUTH")

for ns in todo-dev todo-stage todo-prod; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" create secret generic dockerhub \
    --from-literal=.dockerconfigjson="$DOCKERCFG" \
    --type=kubernetes.io/dockerconfigjson \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "imagePullSecret dockerhub ensured in ${ns}"
done

echo "Done (password not printed)."
