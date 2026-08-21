# Verification status

Three layers of checking sit behind these charts. Each one is honest about what it cannot reach.

<br/>

## What is verified, and how

| Layer | Runs | Covers |
|-------|-----|--------|
| `helm lint --strict` + `kubeconform` | every push (`Helm Lint`) | chart structure, `values.schema.json`, core + CRD manifest schemas |
| kind + `kubectl apply --dry-run=server` | every push (`Chart Validation`) | a real API server validating every render path — 20 cases |
| upstream source cross-check | manually, recorded below | annotation keys and CSI `volumeHandle` formats, which no schema can check |

<br/>

## Why the third layer exists

Ingress annotations live in a `map[string]string` and a CSI `volumeHandle` is a bare string.
A typo in either is valid YAML, valid JSON Schema, and accepted by the Kubernetes API server —
it simply does nothing at runtime. `helm lint`, `kubeconform` and `--dry-run=server` all pass.

Running on the real platform is the only proof. Where that is not available, the next best thing
is checking each literal against the upstream project that consumes it. That is what the table
below records — not proof that the charts work, but evidence that every key and format was taken
from the source of truth rather than invented.

<br/>

## Cross-check results (2026-08-21)

### Azure — Application Gateway Ingress Controller

Source: `Azure/application-gateway-kubernetes-ingress`, `pkg/annotations/ingress_annotations.go`
(21 keys) and `docs/annotations.md`.

| Key used | Found in |
|---|---|
| `appgw.ingress.kubernetes.io/backend-protocol` | source constant |
| `appgw.ingress.kubernetes.io/ssl-redirect` | source constant |
| `appgw.ingress.kubernetes.io/health-probe-path` | source constant |
| `appgw.ingress.kubernetes.io/health-probe-status-codes` | source constant |
| `appgw.ingress.kubernetes.io/request-timeout` | source constant |
| `appgw.ingress.kubernetes.io/connection-draining` | source constant |
| `appgw.ingress.kubernetes.io/connection-draining-timeout` | source constant |
| `appgw.ingress.kubernetes.io/cookie-based-affinity` | source constant |
| `appgw.ingress.kubernetes.io/waf-policy-for-path` | `docs/annotations.md` (handled outside the constants file) |

### Azure — Workload Identity

Source: `Azure/azure-workload-identity`, webhook constants.

| Key used | Found in |
|---|---|
| `azure.workload.identity/client-id` | source constant |
| `azure.workload.identity/use` | source constant |

### GCP — GKE Ingress

Source: `kubernetes/ingress-gce`, `pkg/annotations/{ingress,service}.go`.

| Key used | Found in |
|---|---|
| `kubernetes.io/ingress.class` | source constant |
| `kubernetes.io/ingress.global-static-ip-name` | source constant |
| `networking.gke.io/v1beta1.FrontendConfig` | source constant |
| `cloud.google.com/backend-config` | source constant |
| `networking.gke.io/managed-certificates` | GKE managed-certificates documentation (plural confirmed) |

### CSI volume handle formats

| Driver | Format used | Upstream definition |
|---|---|---|
| `pd.csi.storage.gke.io` | `projects/P/zones/Z/disks/D` | `volIDZonalFmt = "projects/%s/zones/%s/disks/%s"` |
| `filestore.csi.storage.gke.io` | `modeInstance/Z/INSTANCE/SHARE` | `fmt.Sprintf("%s/%s/%s/%s", mode, …)` with `mode == "modeInstance"` |
| `file.csi.azure.com` | `rg#account#share###` | `volumeIDTemplate = "%s#%s#%s#%s#%s#%s"` — six fields, five separators |
| `disk.csi.azure.com` | `/subscriptions/S/resourceGroups/R/providers/Microsoft.Compute/disks/D` | `ManagedDiskPath = "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Compute/disks/%s"` |
| `efs.csi.aws.com` | `fs-…::fsap-…` | EFS access-point handle, as the chart has always rendered it |

<br/>

## Still unverified

Nothing above proves the charts *work* on AKS or GKE — only that their literals match upstream.
Untested end to end: whether the load balancer provisions, whether a BackendConfig health check
takes effect, whether a Rollout promotes through a readiness gate, and whether Filestore or Azure
Files actually mount.

`scripts/gke-smoke.sh` performs those checks on a real GKE cluster. It has not been run — no GKE
project is available here. `base-azure` has no equivalent script, for the same reason.

This is why `base-azure` and `base-gcp` stay at `0.1.0`. They graduate when someone runs them.
