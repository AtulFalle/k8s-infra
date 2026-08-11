# Local TODO app for Compose-based development.
# See docs/DEPLOYMENT_FLOW.md and docs/JOBS_ARCHITECTURE.md.

```bash
docker compose up --build
# open http://localhost:3000
```

CLI jobs (same entrypoint as Kubernetes CronJobs):

```bash
node server.js job cleanup
node server.js job digest
node server.js job fail-once   # exits 1 — for Grafana alert testing
```
