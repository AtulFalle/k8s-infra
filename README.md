# k8s-infra

Kind-based POC: **TODO app Dev → Stage → Prod** with Vault, Grafana, CronJobs, Argo Workflows, and GitOps.

## End-to-end flow

```text
Local dev          CI (GitHub Actions)              Cluster (Argo CD)
─────────          ───────────────────              ─────────────────

docker compose  →  push master (workloads/todo)  →  build + push
                   tag: sha-<git-sha>                 atulfalle1815/todo:sha-…
                   (no commit to master)                    │
                                                            ▼
                                                   Image Updater → todo-dev
                                                   (manual sync)
                                                            │
                     workflow_dispatch: promote stage/prod  │
                     (optional convenience trigger)          ▼
                                                   Argo CD sets tag + syncs stage/prod
```

| Environment | Deploy trigger | Sync mode | Image tag source |
|-------------|----------------|-----------|------------------|
| **Dev** | Every push to `master` (todo paths) | **Manual sync** | `sha-*` via Image Updater (not in Git) |
| **Stage** | Argo CD CLI/UI or optional promote workflow | **Manual sync** | Argo CD app Helm parameter (`image.tag`) |
| **Prod** | Argo CD CLI/UI or optional promote workflow | **Manual sync** | Argo CD app Helm parameter (`image.tag`) |

**Rule:** build once (`sha-<commit>`), promote the same tag to stage/prod.

## 1. Local app development

```bash
cd workloads/todo && docker compose up --build
# http://localhost:3000
```

## 2. Clean Kind cluster (first time)

```bash
bash scripts/fresh-cluster.sh
```

Installs platform only (no demo apps):

| Component | URL |
|-----------|-----|
| TODO dev/stage/prod | http://todo-dev.local … |
| Vault | http://vault.local/ui |
| Grafana | http://grafana.local |
| Headlamp (CronJobs) | http://headlamp.local |
| Argo Workflows | http://workflows.local |
| Argo CD | http://argocd.local |
| Authentik | http://authentik.local |

Hosts file:

```text
127.0.0.1 todo-dev.local todo-stage.local todo-prod.local
127.0.0.1 authentik.local argocd.local vault.local grafana.local
127.0.0.1 headlamp.local workflows.local
```

After `fresh-cluster.sh`, enable GitOps:

```bash
kubectl apply -f apps/workloads/
```

## 3. CI/CD (GitHub Actions)

Workflow: [`.github/workflows/todo.yml`](.github/workflows/todo.yml)

**On push to `master`** (when `workloads/todo/` or chart changes):

1. Build & push `atulfalle1815/todo:sha-<7-char-sha>`
2. **Does not** commit to `master`
3. Deployment sync is handled by Argo CD (manual sync policy)

**Release tag workflow** (Actions → Run workflow, `promote_to=none`):

1. Builds and pushes `sha-<git-sha>`
2. If `release_tag` is provided (for example `v1.2.3`), publishes Docker tag `atulfalle1815/todo:v1.2.3`
3. Creates GitHub Release for the same tag

**Manual promote** (Actions → Run workflow):

1. Choose `stage` or `prod`
2. Leave `image_tag` empty to use latest from dev cluster, or Docker Hub latest `sha-*`
3. Workflow sets Argo CD app override `image.tag=<sha-...>`
4. Workflow syncs **`todo-stage` / `todo-prod`** via `argocd app sync --core` (needs `KUBECONFIG_DATA`)

| Secret | Purpose |
|--------|---------|
| `DOCKERHUB_USERNAME` | Push images + resolve latest tag |
| `DOCKERHUB_TOKEN` | Push images + resolve latest tag |
| `KUBECONFIG_DATA` | Read dev tag from cluster + **set/sync Argo CD app** for stage/prod |

## 4. Verify POC

1. TODO UI shows **Vault connected** + env banner per host
2. Dev `/api/meta` shows `version: sha-…` matching latest CI build
3. Headlamp → `todo-dev` → CronJobs `todo-cleanup`, `todo-digest`
4. Workflows → `todo-digest-pipeline`
5. Promote to stage → manual Argo sync → http://todo-stage.local same `sha-*` tag

## 5. Repo layout

| Path | Purpose |
|------|---------|
| `workloads/todo/` | App source |
| `charts/todo/` | Helm chart + CronJobs |
| `envs/todo/{dev,stage,prod}/` | Per-env config (`image.tag` is runtime-owned by Argo CD) |
| `apps/workloads/todo-*.yaml` | Argo CD Applications |
| `infrastructure/` | Vault, Authentik, Grafana, Headlamp, Workflows, Image Updater |
| `scripts/fresh-cluster.sh` | One-shot clean Kind install |

## Docs

- [docs/DEPLOYMENT_FLOW.md](docs/DEPLOYMENT_FLOW.md)
- [docs/JOBS_ARCHITECTURE.md](docs/JOBS_ARCHITECTURE.md)

## Secrets (never commit)

Generated locally under `infrastructure/authentik/secrets/` (gitignored).  
Init with `bash scripts/init-authentik-secrets.sh`.

Authentik login: `akadmin` / `cat infrastructure/authentik/secrets/bootstrap-password`
