# k8s-infra

Kind-based platform POC: Authentik, Argo CD, Vault, Grafana, Headlamp, Argo Workflows, ingress, and a minimal **TODO** app to prove Dev → Stage → Prod.

## Agreed flow

See **[docs/DEPLOYMENT_FLOW.md](docs/DEPLOYMENT_FLOW.md)** and **[docs/JOBS_ARCHITECTURE.md](docs/JOBS_ARCHITECTURE.md)**.

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
TAG=0.1.2 bash scripts/deploy-todo-poc.sh
```

UI proves the chain when open:

- **env** / **version** from Git values  
- **banner** + **vault: connected** from Vault → External Secrets → pod  
- **CronJobs** run `node server.js job cleanup|digest` on schedule  

### GitHub Actions (Argo CD image flow)

1. Add repo secrets: `DOCKERHUB_USERNAME=atulfalle1815`, `DOCKERHUB_TOKEN=<hub access token>`
2. Push to `master` → builds/pushes `atulfalle1815/todo:sha-…` and bumps `envs/todo/dev/values.yaml`
3. Argo syncs Dev (after this repo is pushed)
4. Actions → Run workflow → promote to `stage` or `prod`

See [docs/DEPLOYMENT_FLOW.md](docs/DEPLOYMENT_FLOW.md).

Hosts to add:

```text
127.0.0.1  todo-dev.local todo-stage.local todo-prod.local
127.0.0.1  authentik.local argocd.local vault.local grafana.local
127.0.0.1  headlamp.local workflows.local
127.0.0.1  demo-dev.local demo-stage.local demo-prod.local
```

## Layout

| Path | Purpose |
|------|---------|
| `docs/DEPLOYMENT_FLOW.md` | Agreed DevOps flow |
| `docs/JOBS_ARCHITECTURE.md` | Scheduled/batch jobs standard |
| `docs/JOBS_POC_PLAN.md` | Jobs POC implementation plan |
| `workloads/todo/` | TODO app source + Compose |
| `charts/todo/` | Helm chart (CronJobs + app) |
| `workflows/todo/` | Argo Workflows reference |
| `envs/todo/{dev,stage,prod}/` | Per-env image tag + config |
| `apps/workloads/todo-*.yaml` | Argo CD Applications |
| `infrastructure/` | Platform (Authentik, Vault, Headlamp, Workflows, …) |
| `scripts/` | Bootstrap / ingress / finalize / todo deploy |

## Platform

```bash
kind create cluster --name kind --config kind-config.yaml
bash scripts/bootstrap-platform.sh
bash scripts/apply-platform-ingress.sh
bash scripts/finalize-poc.sh   # OIDC + Grafana + Headlamp + Workflows
```

### POC login cheat sheet

| App | URL | How |
|-----|-----|-----|
| Authentik | http://authentik.local | `akadmin` + `cat infrastructure/authentik/secrets/bootstrap-password` |
| Argo CD | http://argocd.local | **LOG IN VIA authentik** (group `Argo CD Admins`) |
| Vault | http://vault.local/ui | **OIDC** or token `root` (group `Vault Admins`) |
| Grafana | http://grafana.local | `admin` / `admin` |
| Headlamp | http://headlamp.local | **LOG IN VIA authentik** |
| Argo Workflows | http://workflows.local | **LOG IN VIA authentik** |
| TODO | http://todo-dev.local | Vault banner proves ESO |

Local Argo admin still works:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

## Later

PR previews, Unleash, Postgres + Vault DB secrets, Authentik for kubectl.
