#!/usr/bin/env bash
# Patch Kind CoreDNS so authentik.local (and friends) resolve inside the cluster.
set -euo pipefail

python - <<'PY'
import json, subprocess, textwrap
core = subprocess.check_output(
    ["kubectl", "get", "cm", "coredns", "-n", "kube-system", "-o", "jsonpath={.data.Corefile}"],
    text=True,
)
if "rewrite name exact authentik.local" in core and "rewrite name exact headlamp.local" in core:
    print("CoreDNS already patched")
    raise SystemExit(0)

rewrites = textwrap.dedent("""\
    rewrite name exact authentik.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
    rewrite name exact argocd.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
    rewrite name exact vault.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
    rewrite name exact grafana.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
    rewrite name exact headlamp.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
    rewrite name exact workflows.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
    rewrite name exact todo-dev.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
""")
# Kind uses 4-space indent
needle = "    ready\n"
if needle not in core:
    raise SystemExit(f"unexpected Corefile format:\n{core!r}")
core2 = core.replace(needle, needle + rewrites, 1)
patch = {"data": {"Corefile": core2}}
subprocess.run(
    ["kubectl", "patch", "cm", "coredns", "-n", "kube-system", "--type", "merge", "-p", json.dumps(patch)],
    check=True,
)
print("CoreDNS patched")
PY

kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns --timeout=60s
echo "CoreDNS reload done"
