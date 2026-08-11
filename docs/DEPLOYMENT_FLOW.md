# Agreed deployment flow (POC)

Goal: validate **Compose → PR → Dev → Stage → Prod** with one small TODO app, plus platform pieces (Authentik OIDC, Vault/ESO, Grafana, jobs).

## Pipeline

```text
Docker Compose (local)
        │
        ▼
PR → CI: build image + review
        │
        ▼
Merge to master
        │
        ▼
GitHub Actions: build & push atulfalle1815/todo:sha-<commit>
        │  (no commit back to master)
        ▼
Argo CD Image Updater → todo-dev auto-sync
        │  smoke OK
        ▼
Manual promote workflow (or Argo CLI/UI) → set `todo-stage` image.tag
        │  sync stage app
        ▼
Manual promote workflow (or Argo CLI/UI) → set `todo-prod` image.tag
        │  sync prod app
        ▼
PROD
```

**Rule:** build the image once (`sha-*` tag); promote the same tag. Do not rebuild for Stage/Prod.

## Config vs secrets vs flags

| Type | Store | Example |
|------|--------|---------|
| Non-secret config | Git `envs/todo/<env>/values.yaml` | `APP_ENV`, cron schedule |
| Dev image tag | **Cluster** (Image Updater → Argo helm params) | `sha-abc1234` — not in Git |
| Stage/Prod image tag | **Cluster** (Argo CD app Helm parameter) | promoted `sha-*` |
| Secrets | Vault `secret/<env>/todo` → ESO → pod | `APP_BANNER`, `DEMO_API_KEY` |
| Feature flags | Unleash later | kill switches |

## CI / CD (GitHub Actions)

Workflow: `.github/workflows/todo.yml`

### Dev (automatic)

1. Push to `master` under `workloads/todo/` or `charts/todo/`
2. CI builds & pushes `atulfalle1815/todo:sha-<7-char-sha>`
3. **No bot commit to master**
4. Argo CD Image Updater on `todo-dev` sets `image.tag` → **auto-sync** deploys

### Stage / Prod (manual workflow + Argo CD sync)

1. Actions → **Run workflow** → `promote_to: stage` or `prod`
2. **`image_tag`** optional — resolution order:
   - workflow input (if set)
   - `todo-dev` Deployment image (if `KUBECONFIG_DATA` set)
   - Docker Hub latest `sha-*` tag
3. Workflow sets Argo CD Helm override: `image.tag=<sha-...>` on `todo-{stage|prod}`
4. Workflow syncs **`todo-{stage|prod}`** (`argocd app sync --core`)

Required GitHub secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`  
Required for deploy from CI: `KUBECONFIG_DATA` (base64 kubeconfig)

### Argo CD sync policy

| App | Auto-sync | Notes |
|-----|-----------|-------|
| `todo-dev` | **Yes** | Image tag from Image Updater |
| `todo-stage` | **No** | Tag + sync via Argo CD (workflow is optional convenience) |
| `todo-prod` | **No** | Tag + sync via Argo CD (workflow is optional convenience) |

Required GitHub secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`  
Optional: `KUBECONFIG_DATA` (base64) for promote tag discovery

## Platform (Authentik / Vault / Grafana / Jobs)

**Clean cluster:**

```bash
bash scripts/fresh-cluster.sh
kubectl apply -f apps/workloads/   # enable GitOps after push
```

| Service | URL | Login |
|---------|-----|--------|
| Authentik | http://authentik.local | `akadmin` + bootstrap password file |
| Argo CD | http://argocd.local | Authentik OIDC |
| Vault | http://vault.local/ui | OIDC or token `root` |
| Grafana | http://grafana.local | `admin` / `admin` |
| Headlamp | http://headlamp.local | Authentik OIDC |
| Argo Workflows | http://workflows.local | Authentik OIDC |
| TODO | http://todo-{dev,stage,prod}.local | Vault banner proves ESO |

## TODO app

| Piece | Choice |
|-------|--------|
| App | API + SQLite + CLI jobs |
| Cron | CronJob → `node server.js job <name>` |
| Workflows | `workflows/todo/digest-pipeline.yaml` |
| Deploy | Helm via Argo CD |

See [JOBS_ARCHITECTURE.md](JOBS_ARCHITECTURE.md).

## Success criteria

1. `docker compose up` → add a todo  
2. Push to master → dev deploys `sha-*` without Git tag commit  
3. Vault banner + CronJobs + Headlamp + Workflows operational  
4. Promote same `sha-*` to stage/prod via Argo CD (workflow or manual CLI/UI)  
5. Each env on its `*.local` host  
