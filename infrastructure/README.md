# Platform infrastructure

Versioned config for cluster platform services. Workloads live under `charts/` + `apps/workloads/`.

| Component | Directory | Install method |
|-----------|-----------|----------------|
| ingress-nginx | (Kind static manifest in bootstrap) | `kubectl apply` |
| Argo CD | `argocd/` | upstream install + local Ingress / cmd params |
| Vault | `vault/` | Helm + Ingress + policies |
| External Secrets | `external-secrets/` | Helm |
| Authentik | `authentik/` | Helm + Ingress + local secret files |

Apply Ingresses:

```bash
bash scripts/apply-platform-ingress.sh
```
