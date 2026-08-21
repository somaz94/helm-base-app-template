# Base-Azure Helm Chart

Azure AKS Helm chart for Kubernetes applications — Application Gateway (AGIC), Azure Files / Azure Disk storage, Microsoft Entra Workload Identity.

<br/>

## Overview

Specialized Helm chart for Azure AKS clusters: Application Gateway ingress via AGIC, Azure Files / Azure Disk storage through a driver-neutral PV surface, and Microsoft Entra Workload Identity. Ships the same Argo Rollouts, PDB, ExternalSecret and Gateway API surface as its sibling charts.

<br/>

## Templates

| Template | Resource | Description |
|----------|----------|-------------|
| `deployment.yaml` | Deployment | Main workload with volume mounts, env injection (suppressed when `rollout.enabled`) |
| `rollout.yaml` | Rollout | Argo Rollouts workload rendered *instead of* the Deployment |
| `analysistemplate.yaml` | AnalysisTemplate | Promotion/rollback analysis definitions from `analysisTemplates` |
| `service.yaml` | Service | ClusterIP/NodePort/LoadBalancer with version selector |
| `ingress.yaml` | Ingress | Main ingress (any controller) |
| `ingress-review.yaml` | Ingress | Secondary ingress for review/staging traffic |
| `ingress-health.yaml` | Ingress | Dedicated health check endpoint (no header conditions) |
| `ingress-api-docs.yaml` | Ingress | API documentation endpoint |
| `serviceaccount.yaml` | ServiceAccount | Optional SA with Microsoft Entra Workload Identity annotations |
| `hpa.yaml` | HorizontalPodAutoscaler | CPU/memory-based autoscaling (v2) |
| `configmap.yaml` | ConfigMap | Multiple ConfigMaps with envFrom injection |
| `pv.yaml` | PersistentVolume | Static PVs for any CSI driver or plain NFS |
| `pvc.yaml` | PersistentVolumeClaim | PVCs with optional static PV binding |
| `service-preview.yaml` | Service | Blue-green preview Service (`<fullname>-preview`) |
| `ingress-preview.yaml` | Ingress | Binds the preview Service to an ALB target group |
| `pdb.yaml` | PodDisruptionBudget | Voluntary-disruption floor for the workload |
| `externalsecret.yaml` | ExternalSecret | ESO-managed Secret, injected via `envFrom` |
| `extra-objects.yaml` | any | Escape hatch: arbitrary manifests from `extraObjects` |
| `httproute.yaml` | HTTPRoute | Gateway API route (+ optional HTTPS redirect) |
| `storageclass.yaml` | StorageClass | Optional cluster-scoped StorageClass creation |
| `_helpers.tpl` | - | Helper templates (name, labels, shared pod template) |
| `NOTES.txt` | - | Post-install instructions |

<br/>

## Features

- **Application Gateway (AGIC)**: 4 ingress types (main, review, health, api-docs), plus Gateway API `HTTPRoute`
- **Any storage backend**: static PVs across every CSI driver or plain NFS, plus dynamic provisioning and optional `StorageClass` creation
- **Azure Files / Azure Disk**: via the driver-neutral `storage.persistentVolumes` surface
- **Environment injection**: `environment` value auto-injected as `ENVIRONMENT` env var
- **Version-based routing**: `version` label on pods for canary/blue-green deployments
- **Argo Rollouts delivery**: opt-in blue-green or canary, sharing one pod template with the Deployment
- **PodDisruptionBudget**: optional voluntary-disruption floor
- **External Secrets**: optional ESO `ExternalSecret` injected into the pod via `envFrom`
- **ConfigMap envFrom**: Multiple ConfigMaps auto-loaded as environment variables
- **Microsoft Entra Workload Identity**: ServiceAccount annotations
- **Schema validation**: `values.schema.json` validates input values

<br/>

## Ingress Architecture

```
ALB (shared via group.name)
├── ingress-health.yaml     [priority 1] /health*     → no header condition
├── ingress-api-docs.yaml   [priority 2] /api-docs*   → no header condition
├── ingress.yaml            [priority 3] /*            → Client-Version header match
└── ingress-review.yaml     [priority 4] /*            → Client-Version header match (review)
```

- `group.order`: Lower number = higher priority
- Health and API docs ingresses bypass Client-Version header filtering
- Ingress is controller-neutral: set `ingress.className` and `ingress.annotations` for any controller

<br/>

## Values

<br/>

### Required

| Parameter | Type | Description |
|-----------|------|-------------|
| `replicaCount` | int | Number of pod replicas |
| `image.repository` | string | Container image repository (ECR) |
| `image.pullPolicy` | string | Image pull policy (`Always`, `IfNotPresent`, `Never`) |
| `service.type` | string | Service type (`ClusterIP`, `NodePort`, `LoadBalancer`) |
| `service.port` | int | Service port |

<br/>

### Common Overrides

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environment` | - | Environment name → `ENVIRONMENT` env var |
| `version` | - | Version label for routing |
| `image.tag` | `""` | Image tag — required per service (render fails if unset) |
| `service.targetPort` | `8080` | Container port |
| `ingress.enabled` | `false` | Enable main ALB ingress |
| `ingressReview.enabled` | `false` | Enable review ingress (iOS) |
| `ingressHealth.enabled` | `false` | Enable health check ingress |
| `ingressApiDocs.enabled` | `false` | Enable API docs ingress |
| `autoscaling.enabled` | `false` | Enable HPA |
| `strategy.enabled` | `false` | Enable custom deployment strategy |
| `configs.enabled` | `false` | Enable ConfigMap creation |
| `storage.persistentVolumes.enabled` | `false` | Enable static PV creation |
| `storage.persistentVolumeClaims.enabled` | `false` | Enable PVC creation |
| `storageClasses` | `[]` | Optional cluster-scoped StorageClass creation |

<br/>

### Storage Configuration

`storage.persistentVolumes.items[]` is driver-neutral. `source` defaults to `csi` and `driver`
defaults to `file.csi.azure.com`; set both explicitly for any other backend, or use
`source: nfs` for a plain export.

| Field | Description |
|-------|-------------|
| `source` | `csi` (default) or `nfs` |
| `driver` | CSI driver — defaults to `file.csi.azure.com` |
| `volumeHandle` | Driver-specific volume identifier (required for `csi`) |
| `volumeAttributes` | Driver-specific attributes map |
| `nodeStageSecretRef` | Per-volume credentials — required by `file.csi.azure.com` |
| `mountOptions` | Mount options, e.g. `dir_mode` / `file_mode` for Azure Files |
| `server` / `path` | NFS export, when `source: nfs` |

Dynamic provisioning needs no PV at all — declare only a PVC with a `storageClassName` and let
the provisioner create the volume.

<br/>

### AGIC annotations

| Annotation | Description |
|------------|-------------|
| `appgw.ingress.kubernetes.io/backend-protocol` | `http` or `https` to the pods |
| `appgw.ingress.kubernetes.io/ssl-redirect` | Redirect HTTP to HTTPS at the gateway |
| `appgw.ingress.kubernetes.io/health-probe-path` | Custom health probe path |
| `appgw.ingress.kubernetes.io/request-timeout` | Backend request timeout in seconds |
| `appgw.ingress.kubernetes.io/connection-draining` | Drain connections on backend removal |
| `appgw.ingress.kubernetes.io/cookie-based-affinity` | Session affinity |
| `appgw.ingress.kubernetes.io/waf-policy-for-path` | Attach a WAF policy |

<br/>

## Argo Rollouts Delivery

Opt-in and disabled by default. Requires the [Argo Rollouts controller](https://argo-rollouts.readthedocs.io/)
in the cluster.

When `rollout.enabled=true`, `rollout.yaml` renders a `Rollout` **instead of** the `Deployment` — the
two are mutually exclusive. The pod spec is shared through the `base-azure.podTemplate` helper, so the
Rollout and the Deployment can never drift apart. The existing `<fullname>` Service is reused as the
active Service, and `hpa.yaml` retargets its `scaleTargetRef` to the `Rollout` automatically.

`rollout.strategy` has **no default** — an unset or unknown value fails the render rather than picking
one silently, so every service chooses its delivery mode explicitly per environment.

| Value | Default | Description |
|-------|---------|-------------|
| `rollout.enabled` | `false` | Render a Rollout instead of a Deployment |
| `rollout.strategy` | `""` | **Required** when enabled: `canary` or `blueGreen` |
| `rollout.canary.maxSurge` | `1` | Extra pods above desired during the roll |
| `rollout.canary.maxUnavailable` | `0` | Pods down at once; `0` keeps the target group from ever going 0-healthy |
| `rollout.blueGreen.scaleDownDelaySeconds` | `30` | How long the old ReplicaSet keeps serving after promote |
| `rollout.blueGreen.autoPromotionEnabled` | `false` | `false` = manual `kubectl argo rollouts promote` |
| `rollout.blueGreen.previewReplicaCount` | `null` | `null` = full-replica preview |
| `rollout.analysis.prePromotion.templates` | `[]` | AnalysisTemplate refs gating promotion |
| `rollout.analysis.postPromotion.templates` | `[]` | AnalysisTemplate refs driving auto-rollback |

### Choosing a strategy

**`blueGreen`** swaps the active target group all at once on promotion. It renders the
`<fullname>-preview` Service and, with `ingressPreview.enabled`, a preview Ingress that gives the new
pods their own ALB target group for a pre-promote check.

> **Important:** in a namespace with the ALB pod-readiness-gate injected, blue-green **requires**
> `ingressPreview.enabled=true`. Without a preview target group the preview pods can never report
> Ready, and the promotion hangs indefinitely. `NOTES.txt` warns about this combination at install
> time. Canary needs no preview target group, so it is unaffected.

**`canary`** replaces pods add-before-remove inside the single active target group. `maxUnavailable: 0`
keeps ready at desired so the target group is never 0-healthy, which removes the promotion-time ELB 503
race. It briefly runs old and new pods together, so pick it only where a request may hit either version.

```bash
# blue-green with a preview target group
helm template test charts/base-azure --set image.tag=v1.0.0 \
  --set rollout.enabled=true --set rollout.strategy=blueGreen \
  --set ingressPreview.enabled=true

# canary
helm template test charts/base-azure --set image.tag=v1.0.0 \
  --set rollout.enabled=true --set rollout.strategy=canary
```

<br/>

## Usage with ApplicationSet

This chart is referenced by ApplicationSet definitions:

```yaml
source:
  path: charts/base-azure
  helm:
    valueFiles:
      - '../../values/{project}/{service}/{env}.values.yaml'
```

`values.yaml` provides defaults; environment-specific values files override per deployment.

<br/>

## Validation

```bash
# Lint with chart defaults
helm lint charts/base-azure/

# Lint with your own values file
helm lint charts/base-azure/ -f my-values.yaml

# Strict mode lint (treats warnings as errors, validates against values.schema.json)
helm lint charts/base-azure/ -f my-values.yaml --strict

# Render templates
helm template test charts/base-azure/

# Render with your own values
helm template test charts/base-azure/ -f my-values.yaml

# Debug mode rendering (verbose output on errors)
helm template test charts/base-azure/ -f my-values.yaml --debug

# Lint every environment you keep under values/<project>/<service>/
for env in dev qa prod; do
  echo "=== ${env} ==="
  helm lint charts/base-azure/ -f values/my-project/admin/${env}.values.yaml
done
```

> **Note:** `base-azure` targets AKS — Azure Files / Azure Disk CSI volumes, Application Gateway ingress
> via AGIC, Workload Identity service accounts, and optional Argo Rollouts blue-green / canary
> delivery. Use `base` for self-managed clusters, `base-aws` for EKS, `base-gcp` for GKE.

<br/>

## Schema Management

`values.schema.json` validates values at install/upgrade time. When you add or change fields in `values.yaml`, update the schema to match.

<br/>

### Auto-generate schema with helm plugin

```bash

# Install plugin
helm plugin install https://github.com/losisin/helm-values-schema-json

# Generate schema from values.yaml
cd charts/base-azure
helm schema -input values.yaml -output values.schema.json
```

<br/>

### Manual update

Edit `values.schema.json` directly when adding new fields. Key rules:
- Add new properties under the correct parent object
- Set `type`, `enum`, `minimum`/`maximum` constraints as needed
- Add to `required` array if the field must always be provided
- Run `helm lint` after changes to verify
