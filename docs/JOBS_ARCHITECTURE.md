# Jobs architecture (platform standard)

Scheduled and batch work on this platform follows a **single default** plus **one documented exception**.

## Org rule

> All scheduled work uses **Kubernetes CronJob → Job Pod → app image CLI `job <name>`**.  
> Multi-step orchestration uses **Argo Workflows (CronWorkflow)**.  
> **No in-process cron** in API Deployments. **No HTTP-trigger CronJobs**.

## When to use what

| Job shape | Use | Example |
|-----------|-----|---------|
| Single batch function on a schedule | **CronJob + app CLI** | Nightly cleanup, digest report |
| Multi-step / retry / visible pipeline | **Argo Workflows** | Extract → transform → notify |
| View / suspend / trigger manually | **Headlamp** (Authentik OIDC) | Ops only — not a scheduler |
| Failed runs / duration | **Grafana + Prometheus** | Alerts on `kube_job_failed` |

## App contract (every service)

### One image, two modes

```text
node dist/main.js              → HTTP API (Deployment)
node dist/main.js job <name>   → batch job (CronJob Job Pod, exit 0/1)
```

NestJS teams: use **nest-commander** (or equivalent) for the `job` entrypoint. Share services/DB modules between API and jobs.

### Job handler requirements

Every job must be:

- **Idempotent** — safe if run twice (manual + scheduled)
- **Bounded** — `activeDeadlineSeconds` on CronJob
- **Observable** — structured JSON logs with `job`, `env`, timestamp
- **Secret-aware** — Vault → ESO → same secret as API pod

### GitOps

- Schedules live in `envs/<app>/<env>/values.yaml` under `cronjobs:`
- Helm chart defines CronJob templates; values per env differ (Dev faster than Prod)
- Promote **same image tag** Dev → Stage → Prod; only schedule/config may differ

## Platform components (this POC)

| Component | URL | Role |
|-----------|-----|------|
| CronJobs | — | Default scheduler |
| Headlamp | http://headlamp.local | Ops UI (Authentik OIDC) |
| Argo Workflows | http://workflows.local | Multi-step reference (Authentik OIDC) |
| Grafana | http://grafana.local | Job failure alert `TodoKubernetesJobFailed` |

## TODO app reference

```bash
# Local
node workloads/todo/server.js job cleanup
node workloads/todo/server.js job digest
node workloads/todo/server.js job fail-once   # exits 1
```

Jobs: `cleanup`, `digest`, `fail-once` (see `workloads/todo/server.js`).

CronJobs defined in `charts/todo/templates/cronjob.yaml`, configured per env in `envs/todo/*/values.yaml`.

Multi-step reference: `workflows/todo/digest-pipeline.yaml` (extract → digest).

## Decision tree (for new features)

```text
Can it be one idempotent function?
  YES → CronJob + job CLI
  NO  → Does it need multi-step orchestration?
          YES → Argo Workflows
          NO  → Consider queue workers (future); not in POC
```

## Explicitly not allowed in production

- `@Cron` / `@nestjs/schedule` inside API Deployment (duplicate runs with replicas)
- CronJob calling public HTTP endpoints on the app
- Separate cron products (Cronicle) as the control plane
- Schedules only in application code (must be Git per env)

## Bootstrap

```bash
bash scripts/finalize-poc.sh          # full platform incl. Headlamp + Workflows + OIDC
# Or if platform already up:
bash scripts/bootstrap-jobs-platform.sh
bash scripts/sync-jobs-oidc.sh        # register Headlamp/Workflows in Authentik
```

## See also

- [JOBS_POC_PLAN.md](JOBS_POC_PLAN.md) — implementation phases and verification
- [DEPLOYMENT_FLOW.md](DEPLOYMENT_FLOW.md) — overall DevOps flow
