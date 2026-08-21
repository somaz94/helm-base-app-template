#!/usr/bin/env bash
# Tier 3: validate charts/base-gcp on a REAL GKE cluster.
#
# WHY THIS EXISTS
# scripts/validate-charts.sh proves the manifests are structurally valid. It cannot prove
# they are CORRECT, because the two things most likely to be wrong are invisible to every
# schema:
#   * annotation keys  — `kubernetes.io/ingress.class`, `cloud.google.com/backend-config`,
#     `networking.gke.io/v1beta1.FrontendConfig` live in a map[string]string. A typo is
#     valid YAML, valid JSON-schema, and accepted by the API server. It simply does nothing.
#   * volumeHandle format — `projects/P/zones/Z/disks/D` is a plain string to Kubernetes.
#     Only the CSI driver knows whether it parses.
# This script checks whether GKE ACTS on them, which is the only real proof.
#
# COST: an Autopilot cluster plus one external L7 load balancer. Tear down when done —
# the script does that for you unless you pass --keep.
#
# Usage:
#   scripts/gke-smoke.sh --project MY_PROJECT [--region us-central1] [--keep]
set -euo pipefail
[ -n "${ZSH_VERSION:-}" ] && setopt nonomatch

PROJECT="" ; REGION="us-central1" ; KEEP=0
CLUSTER="chart-smoke"
NS="chart-smoke"
RELEASE="smoke"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --region)  REGION="$2";  shift 2;;
    --keep)    KEEP=1; shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done
[ -n "$PROJECT" ] || { echo "--project is required" >&2; exit 2; }

for bin in gcloud kubectl helm; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done
gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q . \
  || { echo "no active gcloud account; run: gcloud auth login" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"
PREV_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

cleanup() {
  if [ "$KEEP" -eq 0 ]; then
    echo "==> tearing down"
    gcloud container clusters delete "$CLUSTER" --project "$PROJECT" --region "$REGION" --quiet >/dev/null 2>&1 || true
  else
    echo "==> --keep: cluster '$CLUSTER' left running. Delete it with:"
    echo "    gcloud container clusters delete $CLUSTER --project $PROJECT --region $REGION"
  fi
  [ -n "$PREV_CONTEXT" ] && kubectl config use-context "$PREV_CONTEXT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> creating Autopilot cluster (this takes several minutes)"
gcloud container clusters create-auto "$CLUSTER" --project "$PROJECT" --region "$REGION" --quiet
gcloud container clusters get-credentials "$CLUSTER" --project "$PROJECT" --region "$REGION"
CTX="$(kubectl config current-context)"
K=(kubectl --context "$CTX")

"${K[@]}" create namespace "$NS" --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
echo "==> installing charts/base-gcp"
helm upgrade --install "$RELEASE" charts/base-gcp -n "$NS" \
  -f charts/base-gcp/ci/gke-smoke-values.yaml --wait --timeout 10m

FULLNAME="$RELEASE-base-gcp"
rc=0
fail() { printf '  FAIL %s\n' "$1"; rc=1; }
pass() { printf '  ok   %s\n' "$1"; }

echo "==> checking what GKE actually did"

# 1. The CRDs exist on a real GKE cluster and our objects were accepted by them.
if "${K[@]}" -n "$NS" get backendconfig "$FULLNAME" >/dev/null 2>&1; then
  pass "BackendConfig accepted by the GKE CRD"
else
  fail "BackendConfig missing"
fi
if "${K[@]}" -n "$NS" get frontendconfig "$FULLNAME" >/dev/null 2>&1; then
  pass "FrontendConfig accepted by the GKE CRD"
else
  fail "FrontendConfig missing"
fi

# 2. The Service annotation is the one GKE reads. If the key were misspelled the Service
#    would still exist and the Ingress would still work — with a DEFAULT health check.
#    That is the failure mode this whole script is built to catch.
ann=$("${K[@]}" -n "$NS" get svc "$FULLNAME" -o jsonpath='{.metadata.annotations.cloud\.google\.com/backend-config}' 2>/dev/null || true)
if [ -n "$ann" ]; then
  pass "Service carries cloud.google.com/backend-config: $ann"
else
  fail "Service is missing the backend-config annotation"
fi

# 3. The Ingress must actually provision an external IP. A wrong ingress.class leaves it
#    pending forever, which no schema would have flagged.
echo "==> waiting for the load balancer to get an address (up to 10 min)"
addr=""
for _ in $(seq 1 60); do
  addr=$("${K[@]}" -n "$NS" get ingress "$FULLNAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$addr" ] && break
  sleep 10
done
if [ -n "$addr" ]; then
  pass "Ingress provisioned an address: $addr"
else
  fail "Ingress never got an address — check kubernetes.io/ingress.class"
fi

# 4. GKE reflects BackendConfig state on the Ingress. Anything other than HEALTHY here
#    means the health check we asked for is not the one in force.
sleep 30
backends=$("${K[@]}" -n "$NS" get ingress "$FULLNAME" -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/backends}' 2>/dev/null || true)
echo "  backends: ${backends:-<none yet>}"
case "$backends" in
  *HEALTHY*) pass "backend reported HEALTHY (the BackendConfig health check passes)";;
  "")        fail "no backend status yet — the LB may still be settling; re-check by hand";;
  *)         fail "backend not healthy: $backends";;
esac

# 5. Dynamic PD provisioning: proves the storage path end to end without hand-writing a
#    pd.csi volumeHandle.
phase=$("${K[@]}" -n "$NS" get pvc smoke-pvc -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [ "$phase" = "Bound" ]; then
  pass "PVC bound via standard-rwo (pd.csi)"
else
  fail "PVC phase: ${phase:-missing}"
fi

# 6. Serve real traffic through the LB.
if [ -n "$addr" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://$addr/" || echo 000)
  if [ "$code" = "200" ]; then
    pass "HTTP 200 through the load balancer"
  else
    fail "HTTP $code through the load balancer"
  fi
fi

echo
if [ $rc -eq 0 ]; then
  echo "==> base-gcp verified on a real cluster."
  echo "    Remaining unverified: Filestore volumeHandle (needs a Filestore instance),"
  echo "    managed certificates, Cloud Armor, IAP. Those cost more than a smoke test."
else
  echo "==> FAILURES above — see the notes in each check for what a failure means."
fi
exit $rc
