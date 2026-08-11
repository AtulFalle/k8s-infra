# Agreed deployment flow (POC)

Goal: validate **Compose → PR → Dev → Stage → Prod** with one small TODO app.  
No personal sandboxes. No Unleash/analytics/cron in v1 (add later).

## Pipeline

```text
Docker Compose (local)
        │
        ▼
PR → CI: build image + k8s smoke/preview (required) + review
        │
        ▼
Merge to master
        │
        ▼
Argo CD auto-sync → DEV   (image tag / digest from Git values)
        │  smoke OK
        ▼
Promote SAME image tag → STAGE  (Git PR on envs only)
        │  QA validates here for POC (dedicated QA env later if needed)
        ▼
Promote SAME release tag → PROD
```

**Rule:** build the image once; promote the tag. Do not rebuild for Stage/Prod.

## Config vs secrets vs flags

| Type | Store | Example |
|------|--------|---------|
| Non-secret config | Git `envs/todo/<env>/values.yaml` | timeouts, `APP_ENV` |
| Secrets | Vault `secret/<env>/todo` → ESO → pod env | `APP_BANNER`, `DEMO_API_KEY` |
| Images | Docker Hub `atulfalle1815/todo` | tag promoted Dev→Stage→Prod |
| Feature flags | Unleash later | kill switches without redeploy |

## CI / CD (GitHub Actions)

Workflow: `.github/workflows/todo.yml`

1. Push to `master` (paths under `workloads/todo`, chart, envs) → build & push `atulfalle1815/todo:sha-…`
2. Bot commits updated `envs/todo/dev/values.yaml` tag → Argo syncs Dev
3. Actions → **Run workflow** → promote to `stage` or `prod` (copies Dev tag)

Required GitHub secrets:

- `DOCKERHUB_USERNAME` = `atulfalle1815`
- `DOCKERHUB_TOKEN` = Docker Hub access token (Account Settings → Security)

Local Kind also needs an `imagePullSecret` named `dockerhub` (see `scripts/create-dockerhub-pull-secret.sh`).


## TODO app (this POC)

| Piece | Choice |
|-------|--------|
| App | Single container: API + static UI + SQLite |
| Local | `workloads/todo/docker-compose.yml` |
| Deploy | Helm `charts/todo` + Argo Apps |
| Hosts | `todo-dev.local`, `todo-stage.local`, `todo-prod.local` |

QA uses **Stage** in this POC to avoid an extra environment.

## DevOps promote (manual for now)

```bash
# 1) Build & load into Kind (local registry/CI later)
docker build -t todo:0.1.0 workloads/todo
kind load docker-image todo:0.1.0

# 2) Set tag in envs/todo/dev/values.yaml → commit → Argo syncs Dev

# 3) After Dev OK: copy same tag to envs/todo/stage/values.yaml → PR → merge

# 4) After Stage/QA OK: copy same tag to envs/todo/prod/values.yaml → PR → merge
```

## Later (not blocking this POC)

- Authentik OIDC for kubectl / Vault / Argo  
- PR preview ApplicationSet  
- Unleash feature flags  
- Postgres instead of SQLite  
- Grafana / cron dashboards  
- Dedicated QA namespace  

## Success criteria for this POC

1. `docker compose up` → add a todo in the UI  
2. Image on Docker Hub `atulfalle1815/todo` runs in Dev/Stage/Prod via Helm/Argo  
3. UI shows **Vault connected** + per-env banner (ESO synced)  
4. Same image tag promoted Dev → Stage → Prod via Git values / Actions  
5. Each env reachable on its `*.local` host  
