# Platform infrastructure

Versioned config for cluster platform services. Workloads live under `charts/` + `apps/workloads/`.

| Component | Directory | Install method |
|-----------|-----------|----------------|
| ingress-nginx | (Kind static manifest in bootstrap) | `kubectl apply` |
| Argo CD | `argocd/` | upstream install + local Ingress / cmd params |
| Vault | `vault/` | Helm + Ingress + policies |
| External Secrets | `external-secrets/` | Helm |
| Authentik | `authentik/` | Helm + Ingress + local secret files |
| Headlamp | `headlamp/` | Helm + Authentik OIDC |
| Argo Workflows | `argo-workflows/` | Helm + Authentik OIDC |
| Argo CD Image Updater | `argocd-image-updater/` | Dev sha auto-deploy |
| Monitoring | `monitoring/` | kube-prometheus-stack + job alerts |

Apply Ingresses:

```bash
bash scripts/apply-platform-ingress.sh
```
