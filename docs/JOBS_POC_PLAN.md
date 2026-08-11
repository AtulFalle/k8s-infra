# Jobs architecture — POC implementation plan

This document is the **implementation plan** for scheduled/batch work on the Kind platform.  
It locks the production-grade pattern before app development starts.

**Status:** Implemented — see [JOBS_ARCHITECTURE.md](JOBS_ARCHITECTURE.md).

---

## Architecture decision (final)

### Org standard

> All scheduled work uses **Kubernetes CronJob → Job Pod → app image CLI `job <name>`**.  
> Multi-step orchestration uses **Argo Workflows (CronWorkflow)**.  
> **No in-process cron**, **no HTTP-trigger CronJobs**.

### Boundaries

| Job shape | Scheduler | Where logic lives |
|-----------|-----------|-------------------|
| Single batch function on a schedule | **Kubernetes CronJob** | App image CLI (`node server.js job <name>`) |
| Multi-step / retry / visible pipeline | **Argo Workflows** | Workflow YAML + optional app CLI steps |
| Ops (view / suspend / trigger) | **Headlamp** | Platform UI (not a scheduler) |
| Failures / duration | **Grafana** | Observability (not a scheduler) |

### Platform glue (unchanged)

- **Git + Argo CD** — schedules and workflow defs per env  
- **Vault + ESO** — secrets in Job Pods same as API  
- **Authentik OIDC** — Headlamp + Argo Workflows UI  

### Explicitly out of scope

- Temporal, BullMQ, Airflow, Cronicle  
- In-app `@Cron` / `@nestjs/schedule` in production API pods  
- HTTP `POST /api/maintenance/*` triggered by CronJob  
- `curlimages/curl` sidecar CronJobs  

---

## Current state vs target

| Area | Current | Target |
|------|---------|--------|
| TODO app | HTTP server only; `POST /api/maintenance/cleanup-done` | CLI mode: `node server.js job <name>`; remove maintenance HTTP route |
| CronJob chart | `curlimages/curl` → POST to API | Same **todo image** + `command: ["node","server.js","job","cleanup"]` |
| Chart values | Single `cronjob:` block | `cronjobs:` map (cleanup, digest, fail-once) per job |
| Env schedules | Dev `*/5`, others similar | Dev fast, Stage slower, Prod hourly; `concurrencyPolicy: Forbid` |
| Job secrets | ESO on Deployment only | CronJob Pod uses same `envFrom` secret + PVC for SQLite |
| Ops UI | kubectl / Argo CD resource view | **Headlamp** @ `headlamp.local` + Authentik OIDC |
| Multi-step | None | **Argo Workflows** @ `workflows.local` — one 2-step CronWorkflow |
| Monitoring | Grafana installed | Dashboard or alert for failed Kubernetes Jobs |
| Docs | DEPLOYMENT_FLOW mentions curl cron | Link to this plan + `JOBS_ARCHITECTURE.md` (rules for app teams) |

---

## POC jobs (minimal app code)

Three CLI jobs on the TODO app — stubs only, no business complexity.

| Job name | Purpose | Exit |
|----------|---------|------|
| `cleanup` | `DELETE FROM todos WHERE done = 1` | 0 |
| `digest` | Log todo count + prove Vault secret loaded (`DEMO_API_KEY` fingerprint) | 0 |
| `fail-once` | Log error, exit 1 | 1 (disabled by default; enable to test Grafana) |

**App entry pattern:**

```text
node server.js              → HTTP API (Deployment)
node server.js job cleanup  → run job, exit
node server.js job digest
node server.js job fail-once
```

---

## Implementation phases

### Phase 1 — App CLI + CronJob chart (foundation)

**Goal:** Replace legacy HTTP/curl cron with the production default.

**Tasks:**

1. Refactor `workloads/todo/server.js`:
   - Extract job functions (`cleanup`, `digest`, `fail-once`).
   - If `process.argv[2] === 'job'`, run job and `process.exit(code)`.
   - Remove `POST /api/maintenance/cleanup-done`.
2. Update `charts/todo/templates/cronjob.yaml`:
   - Generic template over `.Values.cronjobs` map (or separate template per job).
   - Container: **same image** as Deployment.
   - `command: ["node", "server.js", "job", "<name>"]`.
   - `concurrencyPolicy: Forbid`, `activeDeadlineSeconds`, history limits.
   - Same `env`, `envFrom`, `volumeMounts` (PVC) as Deployment.
   - `restartPolicy: OnFailure`, `backoffLimit: 0` or `1`.
3. Update `charts/todo/values.yaml`:
   ```yaml
   cronjobs:
     cleanup:
       enabled: true
       schedule: "*/10 * * * *"
       job: cleanup
     digest:
       enabled: true
       schedule: "0 * * * *"
       job: digest
     fail-once:
       enabled: false
       schedule: "*/30 * * * *"
       job: fail-once
   ```
4. Update `envs/todo/{dev,stage,prod}/values.yaml` — different schedules per env.
5. Bump image tag; rebuild/push via CI or local script.

**Files touched:**

- `workloads/todo/server.js`
- `charts/todo/templates/cronjob.yaml` (or `cronjob-*.yaml`)
- `charts/todo/values.yaml`
- `envs/todo/dev|stage|prod/values.yaml`
- `docs/DEPLOYMENT_FLOW.md` (cron row)
- `readme.md` (remove curl cron mention)

**Verify:**

```bash
kubectl -n todo-dev get cronjobs,jobs,pods
kubectl -n todo-dev logs job/<cleanup-job-name>
# Mark todos done in UI → wait for schedule → done items removed
kubectl -n todo-dev logs job/<digest-job-name>  # shows count + vault fingerprint
```

---

### Phase 2 — Headlamp + Authentik OIDC (ops UI)

**Goal:** View, suspend, and manually trigger CronJobs without kubectl.

**Tasks:**

1. Add `infrastructure/headlamp/`:
   - `values.yaml` — lightweight Kind resources, ingress `headlamp.local`.
   - `ingress.yaml` (if not via Helm ingress).
2. Extend Authentik blueprint `poc-oidc-apps.yaml`:
   - OAuth2 provider + application for Headlamp.
   - Group e.g. **Platform Admins** (or reuse **Argo CD Admins** for POC).
3. Extend `infrastructure/authentik/secrets/` + `finalize-poc.sh`:
   - `headlamp-client-id`, `headlamp-client-secret`.
   - Wire env vars into Authentik Helm like Argo/Vault.
4. CoreDNS: add `headlamp.local` rewrite in `infrastructure/coredns/custom.yaml`.
5. Install Headlamp in `finalize-poc.sh` (or new `scripts/bootstrap-jobs-platform.sh`).
6. Configure Headlamp OIDC (issuer, client ID/secret, redirect URI).

**Files touched:**

- `infrastructure/headlamp/values.yaml`
- `infrastructure/headlamp/ingress.yaml`
- `infrastructure/authentik/blueprints/poc-oidc-apps.yaml`
- `infrastructure/authentik/values.yaml`
- `scripts/finalize-poc.sh`
- `infrastructure/coredns/custom.yaml`
- `readme.md`, `docs/DEPLOYMENT_FLOW.md`

**Verify:**

- Login at http://headlamp.local via Authentik.
- Navigate to `todo-dev` namespace → CronJobs → suspend cleanup → resume.
- Create Job from CronJob → manual run completes.

---

### Phase 3 — Argo Workflows (multi-step reference)

**Goal:** Prove the **exception path** for multi-step scheduled work.

**Tasks:**

1. Add `infrastructure/argo-workflows/`:
   - Helm install (argo-workflows chart or upstream manifest).
   - Server ingress @ `workflows.local`.
   - SSO mode: OIDC via Authentik (same blueprint pattern).
2. Add `workflows/todo/digest-pipeline.yaml`:
   - `WorkflowTemplate` or inline `CronWorkflow` with 2 steps:
     - Step 1: `echo` / log “extract”
     - Step 2: run todo image `job digest` (or `curl` internal — prefer app CLI)
   - Schedule e.g. `0 */6 * * *` (POC only).
3. Argo CD Application for workflows (optional) or apply via script.
4. Authentik blueprint: **Argo Workflows** OAuth app + group mapping.
5. CoreDNS: `workflows.local`.

**Files touched:**

- `infrastructure/argo-workflows/values.yaml`
- `infrastructure/argo-workflows/ingress.yaml`
- `workflows/todo/digest-pipeline.yaml`
- `apps/platform/argo-workflows.yaml` (optional)
- Authentik blueprint + secrets + finalize script
- CoreDNS, docs

**Verify:**

- http://workflows.local — login via Authentik.
- CronWorkflow visible; manual submit runs 2 steps.
- Step 2 logs digest output in pod logs.

---

### Phase 4 — Grafana job observability

**Goal:** See failed Jobs without kubectl.

**Tasks:**

1. Extend `infrastructure/monitoring/values.yaml` or add:
   - `infrastructure/monitoring/dashboards/job-failures.json` (ConfigMap).
   - Or PrometheusRule alert: `kube_job_status_failed > 0`.
2. Document how to enable `fail-once` cronjob in dev to test alert.
3. Optional: Grafana OIDC via Authentik (later; admin/admin OK for POC).

**Files touched:**

- `infrastructure/monitoring/values.yaml` or dashboard ConfigMap
- `docs/JOBS_POC_PLAN.md` (mark verify steps)
- `envs/todo/dev/values.yaml` (comment for fail-once toggle)

**Verify:**

- Enable `cronjobs.fail-once.enabled: true` in dev.
- After run, failed Job visible in Grafana dashboard or alert fires.

---

### Phase 5 — Documentation + app-team contract

**Goal:** Single reference for real app implementation.

**Tasks:**

1. Create `docs/JOBS_ARCHITECTURE.md` (rules, decision tree, NestJS mapping notes).
2. Update `docs/DEPLOYMENT_FLOW.md`:
   - Replace curl cron with CLI cron.
   - Add Headlamp / Workflows URLs to platform table.
   - Link to JOBS docs.
3. Update `readme.md` hosts + login cheat sheet.
4. Add success criteria to DEPLOYMENT_FLOW.

**Files touched:**

- `docs/JOBS_ARCHITECTURE.md` (new)
- `docs/DEPLOYMENT_FLOW.md`
- `readme.md`

---

## Target repo layout (after all phases)

```text
workloads/todo/
  server.js                    # API + job CLI

charts/todo/
  templates/
    cronjob.yaml                 # values-driven CronJobs (app image)
    deployment.yaml
    ...
  values.yaml                    # cronjobs: map

envs/todo/{dev,stage,prod}/
  values.yaml                    # per-env schedules

workflows/todo/
  digest-pipeline.yaml           # Argo CronWorkflow (2 steps)

infrastructure/
  headlamp/
  argo-workflows/
  monitoring/                    # + job failure dashboard
  authentik/blueprints/          # + Headlamp + Workflows OIDC
  coredns/custom.yaml            # + headlamp.local, workflows.local

docs/
  JOBS_POC_PLAN.md               # this file
  JOBS_ARCHITECTURE.md           # app-team standard (Phase 5)
```

---

## Hosts file (after implementation)

```text
127.0.0.1 authentik.local argocd.local vault.local grafana.local
127.0.0.1 headlamp.local workflows.local
127.0.0.1 todo-dev.local todo-stage.local todo-prod.local
```

---

## Success criteria (jobs POC complete)

1. CronJob runs **todo image** with `job cleanup`; completed todos removed — no curl, no HTTP maintenance route.
2. `job digest` runs on schedule; logs todo count and Vault secret fingerprint.
3. Dev / Stage / Prod schedules differ via Git only; Argo CD syncs.
4. Headlamp @ `headlamp.local`: Authentik login, list CronJobs, suspend, trigger Job.
5. Argo Workflows @ `workflows.local`: one CronWorkflow with 2 steps; manual submit works.
6. Failed Job (`fail-once`) visible in Grafana when enabled in dev.
7. `docs/JOBS_ARCHITECTURE.md` documents the standard for future NestJS services.

---

## Implementation order & effort

| Phase | Depends on | Est. size | Start when |
|-------|------------|-----------|------------|
| **1** App CLI + CronJob | — | Small | **First** |
| **2** Headlamp + OIDC | Phase 1 | Medium | After Phase 1 verified |
| **3** Argo Workflows | Phase 1 | Medium | Can parallel with Phase 2 |
| **4** Grafana jobs | Phase 1 | Small | After Phase 1; needs fail-once job |
| **5** Docs | Phases 1–4 | Small | Last |

**Recommended sequence:** `1 → 2 → 3 → 4 → 5`  
Phases 2 and 3 can run in parallel if two people implement.

---

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| CronJob Pod can’t access SQLite on PVC | Mount same PVC in Job template; `ReadWriteOnce` OK if API scaled to 1 replica in POC |
| Job Pod missing Vault env | Reuse Deployment `envFrom` + serviceAccount in CronJob spec |
| Headlamp / Workflows OIDC callback mismatch | Strict redirect URIs in Authentik; CoreDNS rewrite for issuer |
| Argo CD self-heal vs local helm test | Document: change Git values only when Argo owns app |
| Kind resource pressure | Keep Workflows + Headlamp lightweight; single replicas |

---

## Next step

**Start Phase 1** when approved:

1. Refactor `server.js` for job CLI.
2. Rewrite CronJob template to use app image.
3. Update values per env.
4. Build/push new todo image tag.

Say **“start Phase 1”** to begin implementation.
