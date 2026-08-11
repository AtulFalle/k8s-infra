# k8s-infra

Kind-based platform POC: Authentik, Argo CD, Vault, ingress, and a minimal **TODO** app to prove Dev → Stage → Prod.

## Agreed flow

See **[docs/DEPLOYMENT_FLOW.md](docs/DEPLOYMENT_FLOW.md)**.

```text
Compose (local) → PR (build + k8s check + review) → merge
  → Argo DEV → promote same image tag → STAGE (QA) → PROD
```

## TODO POC (quick)

```bash
# Local
cd workloads/todo && docker compose up --build
# http://localhost:3000

# Kind + Docker Hub + Vault (full E2E)
bash scripts/deploy-todo-poc.sh
```

UI proves the chain when open:

- **env** / **version** from Git values  
- **banner** + **vault: connected** from Vault → External Secrets → pod  

### GitHub Actions (Argo CD image flow)

1. Add repo secrets: `DOCKERHUB_USERNAME=atulfalle1815`, `DOCKERHUB_TOKEN=<hub access token>`
2. Push to `master` → builds/pushes `atulfalle1815/todo:sha-…` and bumps `envs/todo/dev/values.yaml`
3. Argo syncs Dev (after this repo is pushed)
4. Actions → Run workflow → promote to `stage` or `prod`

See [docs/DEPLOYMENT_FLOW.md](docs/DEPLOYMENT_FLOW.md).

Hosts to add:

```text
127.0.0.1  todo-dev.local todo-stage.local todo-prod.local
127.0.0.1  authentik.local argocd.local vault.local
127.0.0.1  demo-dev.local demo-stage.local demo-prod.local
```

## Layout

| Path | Purpose |
|------|---------|
| `docs/DEPLOYMENT_FLOW.md` | Agreed DevOps flow |
| `workloads/todo/` | TODO app source + Compose |
| `charts/todo/` | Helm chart |
| `envs/todo/{dev,stage,prod}/` | Per-env image tag + config |
| `apps/workloads/todo-*.yaml` | Argo CD Applications |
| `infrastructure/` | Platform (Authentik, Vault, Argo ingress, …) |
| `scripts/` | Bootstrap / ingress / todo deploy |

## Platform

```bash
kind create cluster --name kind --config kind-config.yaml
bash scripts/bootstrap-platform.sh
bash scripts/apply-platform-ingress.sh
```

Argo CD password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

## Later

OIDC (kubectl/Vault), PR previews, Unleash, Postgres+Vault secrets, Grafana/cron.
