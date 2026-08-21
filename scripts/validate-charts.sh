#!/usr/bin/env bash
# Validate every chart against REAL Kubernetes API schemas, without a cloud account.
#
# Two layers, because neither alone is enough:
#   1. kind + `kubectl apply --dry-run=server` — the API server validates against the
#      CRDs actually installed, catching wrong apiVersions, unknown fields and bad types.
#   2. kubeconform + the datreeio CRD catalog — covers CRDs that only exist on a managed
#      cloud (GKE's BackendConfig / FrontendConfig), which kind cannot install.
#
# NEITHER catches a misspelled ingress annotation: annotations are map[string]string, so
# `appgw.ingress.kubernetes.io/health-probe-path` typo'd is valid to every schema there is.
# Only a real cluster settles that.
#
# Usage: scripts/validate-charts.sh [--keep]     (--keep leaves the kind cluster running)
set -euo pipefail
[ -n "${ZSH_VERSION:-}" ] && setopt nonomatch

CLUSTER='chart-validate'
CTX="kind-${CLUSTER}"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1
CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

cleanup() { [ "$KEEP" -eq 1 ] || kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "==> creating kind cluster '$CLUSTER'"
  kind create cluster --name "$CLUSTER" --wait 90s >/dev/null
fi

# Always target the kind context explicitly. Never inherit the caller's current context —
# it may well be a production cluster.
K=(kubectl --context "$CTX")

echo "==> installing CRDs (server-side: the bundles exceed the annotation size limit)"
"${K[@]}" apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml >/dev/null
"${K[@]}" apply --server-side -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml >/dev/null
"${K[@]}" apply --server-side -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml >/dev/null
"${K[@]}" create namespace validate --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null

rc=0
check() {
  local chart=$1 label=$2; shift 2
  local rendered out
  if ! rendered=$(helm template t "charts/$chart" -n validate "$@" 2>&1); then
    printf '  FAIL %-11s %-24s render: %s\n' "$chart" "$label" \
      "$(printf '%s' "$rendered" | grep -oE 'Error:.*' | head -1)"; rc=1; return
  fi
  # kind cannot install managed-cloud CRDs (GKE BackendConfig / FrontendConfig), so those
  # kinds are withheld from the API server and covered by kubeconform below instead.
  local server_input
  server_input=$(printf '%s' "$rendered" | python3 -c '
import sys, yaml
SKIP = {"BackendConfig", "FrontendConfig"}
keep = [d for d in yaml.safe_load_all(sys.stdin) if d and d.get("kind") not in SKIP]
print(yaml.safe_dump_all(keep, default_flow_style=False))')
  if ! out=$(printf '%s' "$server_input" | "${K[@]}" apply -n validate --dry-run=server -f - 2>&1); then
    printf '  FAIL %-11s %-24s server dry-run\n' "$chart" "$label"
    printf '%s' "$out" | grep -iE 'error|invalid|unknown' | head -3 | sed 's/^/         /'; rc=1; return
  fi
  local n; n=$(printf '%s' "$out" | grep -c 'server dry run')
  # Managed-cloud CRDs kind cannot install: validate those against the published catalog.
  if ! printf '%s' "$rendered" | kubeconform -strict -summary \
        -schema-location default -schema-location "$CATALOG" >/dev/null 2>&1; then
    printf '  FAIL %-11s %-24s kubeconform\n' "$chart" "$label"
    printf '%s' "$rendered" | kubeconform -strict -schema-location default \
      -schema-location "$CATALOG" 2>&1 | grep -i invalid | head -3 | sed 's/^/         /'; rc=1; return
  fi
  printf '  ok   %-11s %-24s %2s objects\n' "$chart" "$label" "$n"
}

echo "==> validating"
for c in base base-aws base-azure base-gcp; do
  check "$c" default -f "charts/$c/ci/lint-values.yaml"
  [ -f "charts/$c/ci/rollout-values.yaml" ] && check "$c" "rollout canary" -f "charts/$c/ci/rollout-values.yaml"
  check "$c" httproute --set image.tag=v1 --set httproute.enabled=true \
    --set 'httproute.parentRefs[0].name=gw' --set 'httproute.hostnames[0]=app.example.com' \
    --set 'httproute.rules[0].matches[0].path.type=PathPrefix' \
    --set 'httproute.rules[0].matches[0].path.value=/'
done
for c in base-aws base-azure base-gcp; do
  check "$c" "blueGreen + preview" --set image.tag=v1 --set rollout.enabled=true \
    --set rollout.strategy=blueGreen --set ingressPreview.enabled=true \
    --set 'ingressPreview.hosts[0].host=preview.example.com' \
    --set 'ingressPreview.hosts[0].paths[0].path=/' \
    --set 'ingressPreview.hosts[0].paths[0].pathType=Prefix'
  check "$c" "pdb + eso + sc" --set image.tag=v1 --set podDisruptionBudget.enabled=true \
    --set externalSecrets.enabled=true --set externalSecrets.secretStoreRef.name=store \
    --set 'externalSecrets.dataFrom[0].extract.key=prod/app' \
    --set 'storageClasses[0].name=sc-test' --set 'storageClasses[0].provisioner=x.csi.io'
done
# GKE-only CRDs, both with and without a populated spec: an enabled-but-unconfigured
# BackendConfig used to render spec: null, which the CRD schema rejects.
check base-gcp "gke config (empty)" --set image.tag=v1 \
  --set backendConfig.enabled=true --set frontendConfig.enabled=true
check base-gcp "gke config (populated)" --set image.tag=v1 \
  --set backendConfig.enabled=true --set backendConfig.timeoutSec=30 \
  --set backendConfig.healthCheck.type=HTTP --set backendConfig.healthCheck.requestPath=/health \
  --set frontendConfig.enabled=true --set frontendConfig.sslPolicy=my-ssl

[ $rc -eq 0 ] && echo "==> all charts valid" || echo "==> FAILURES above"
exit $rc
