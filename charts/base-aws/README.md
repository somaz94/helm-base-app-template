# Base-AWS Helm Chart

AWS EKS Helm chart for Kubernetes applications.

<br/>

## Overview

Specialized Helm chart for AWS EKS clusters with driver-neutral static storage (EFS CSI by default), AWS ALB ingress (including header-based routing), multiple ingress types, and Gateway API HTTPRoute. Used by ArgoCD ApplicationSet with Matrix Generator pattern.

<br/>

## Templates

The [templates/](templates/) directory is the SSOT for the full set of rendered resources — the file name is the resource, so the listing is not duplicated here.

Grouped by feature:

- **Workload**: Deployment or an Argo Rollouts Rollout (`rollout.enabled` picks one), Service, ServiceAccount (IRSA), HorizontalPodAutoscaler, PodDisruptionBudget, ConfigMap
- **Traffic**: purpose-specific ALB Ingresses sharing a single ALB group, plus a Gateway API HTTPRoute
- **Progressive delivery**: blue-green preview Service and the AnalysisTemplates backing the promotion gate / auto-rollback signal
- **Storage**: driver-neutral static PersistentVolume, PersistentVolumeClaim, optional StorageClass
- **Secrets & escape hatch**: ExternalSecret (External Secrets Operator) and arbitrary manifests via extraObjects

Everything except Deployment and Service is toggled by an `enabled` flag (or a list value) in `values.yaml`.

<br/>

## Features

- **AWS ALB Ingress**: purpose-specific ingresses share a single ALB via `group.name`, each enabled independently by its own toggle
- **Client-Version routing**: Header-based routing via ALB conditions/actions annotations
- **Driver-neutral storage**: Static PVs for EFS / Azure Files & Disk / GCP Filestore & PD / plain NFS. The EFS shorthand (`fileSystemId`[+`accessPointId`]) keeps working unchanged
- **Gateway API HTTPRoute**: Ingress alternative that works with any GatewayClass (off by default)
- **Environment injection**: `environment` value auto-injected as `ENVIRONMENT` env var
- **Version-based routing**: `version` label on pods for canary/blue-green deployments
- **Argo Rollouts delivery**: opt-in blue-green or canary, sharing one pod template with the Deployment
- **PodDisruptionBudget**: optional voluntary-disruption floor
- **External Secrets**: optional ESO `ExternalSecret` injected into the pod via `envFrom`
- **ConfigMap envFrom**: Multiple ConfigMaps auto-loaded as environment variables
- **IRSA support**: ServiceAccount annotations for IAM Roles for Service Accounts
- **Schema validation**: `values.schema.json` validates input values

<br/>

## Ingress Architecture

Every `ingress*` template joins one ALB by sharing the same `alb.ingress.kubernetes.io/group.name`. Which ingresses render is decided by their individual `enabled` toggles; their match order inside the ALB group is decided by the `alb.ingress.kubernetes.io/group.order` annotation set on each one. That annotation is the SSOT for priority, so the ordering is not duplicated here.

- `group.order`: Lower number = higher priority
- Public-endpoint ingresses such as health and API docs bypass Client-Version header filtering
- Main and review ingresses use `alb.ingress.kubernetes.io/conditions.*` for header-based routing

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
| `ingressPreview.enabled` | `false` | Enable blue-green preview ingress (blueGreen rollout only) |
| `autoscaling.enabled` | `false` | Enable HPA |
| `podDisruptionBudget.enabled` | `false` | Enable a PodDisruptionBudget (only meaningful at replicas >= 2) |
| `strategy.enabled` | `false` | Enable custom deployment strategy |
| `rollout.enabled` | `false` | Render an Argo Rollouts Rollout instead of a Deployment (`rollout.strategy` required) |
| `analysisTemplates` | `[]` | AnalysisTemplates for the promotion gate / auto-rollback signal |
| `configs.enabled` | `false` | Enable ConfigMap creation |
| `externalSecrets.enabled` | `false` | Enable ExternalSecret creation and envFrom secretRef injection |
| `efs.persistentVolumes.enabled` | `false` | Enable static PV creation |
| `efs.persistentVolumeClaims.enabled` | `false` | Enable PVC creation |
| `httproute.enabled` | `false` | Enable Gateway API HTTPRoute creation |
| `storageClasses` | `[]` | StorageClasses to create (nothing renders while empty) |

This table covers the commonly used toggles only. `values.yaml` and `values.schema.json` are the SSOT for the full key set and its constraints; the table tracks them.

<br/>

### Storage Configuration

The `efs:` key name is kept for backward compatibility, but PV items themselves are driver-neutral. Each item picks a volume shape with `source` (defaults to `csi`).

| Parameter | Description |
|-----------|-------------|
| `source` | Volume shape — `csi` (default) or `nfs` |
| `driver` | CSI driver (defaults to `efs.csi.aws.com`) |
| `volumeHandle` | CSI volume handle. Falls back to `fileSystemId`[`::accessPointId`] when unset |
| `volumeAttributes` | CSI volume attribute map. Falls back to the `subPath` shorthand when unset |
| `nodeStageSecretRef` / `nodePublishSecretRef` | For drivers that authenticate per volume (e.g., `file.csi.azure.com`) |
| `fsType` / `mountOptions` / `readOnly` | Block volume and mount options |
| `server` / `path` | `source: nfs` only — NFS server and export path |
| `fileSystemId` | EFS file system ID shorthand (e.g., `fs-0123456789abcdef0`) |
| `accessPointId` | EFS Access Point ID (optional, e.g., `fsap-0123456789abcdef0`) |
| `subPath` | Path, only meaningful when no Access Point is used |
| `storage` | Storage capacity (e.g., `5Gi`) |
| `storageClassName` | Storage class (e.g., `efs-sc`) |

At least one of `volumeHandle` / `fileSystemId` / (`server` + `path`) must be present; the `anyOf` in `values.schema.json` enforces it.

<br/>

### ALB Ingress Configuration

Key ALB annotations used:

| Annotation | Description |
|------------|-------------|
| `alb.ingress.kubernetes.io/scheme` | `internet-facing` or `internal` |
| `alb.ingress.kubernetes.io/target-type` | `ip` (required for Fargate/VPC CNI) |
| `alb.ingress.kubernetes.io/group.name` | Shared ALB group name |
| `alb.ingress.kubernetes.io/group.order` | Priority within ALB group (-1000 to 1000, default 0) |
| `alb.ingress.kubernetes.io/certificate-arn` | ACM certificate ARN for TLS |
| `alb.ingress.kubernetes.io/conditions.*` | Header/path-based routing conditions |
| `alb.ingress.kubernetes.io/actions.*` | Target group forwarding actions |

<br/>

## Argo Rollouts Delivery

Opt-in and disabled by default. Requires the [Argo Rollouts controller](https://argo-rollouts.readthedocs.io/)
in the cluster.

When `rollout.enabled=true`, `rollout.yaml` renders a `Rollout` **instead of** the `Deployment` — the
two are mutually exclusive. The pod spec is shared through the `base-aws.podTemplate` helper, so the
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
helm template test charts/base-aws --set image.tag=v1.0.0 \
  --set rollout.enabled=true --set rollout.strategy=blueGreen \
  --set ingressPreview.enabled=true

# canary
helm template test charts/base-aws --set image.tag=v1.0.0 \
  --set rollout.enabled=true --set rollout.strategy=canary
```

<br/>

## Usage with ApplicationSet

This chart is referenced by ApplicationSet definitions:

```yaml
source:
  path: charts/base-aws
  helm:
    valueFiles:
      - '../../values/{project}/{service}/{env}.values.yaml'
```

`values.yaml` provides defaults; environment-specific values files override per deployment.

<br/>

## Validation

```bash
# Lint with chart defaults
helm lint charts/base-aws/

# Lint with your own values file
helm lint charts/base-aws/ -f my-values.yaml

# Strict mode lint (treats warnings as errors, validates against values.schema.json)
helm lint charts/base-aws/ -f my-values.yaml --strict

# Render templates. image.tag is required per service, so a bare render fails by
# design — supply it from your values file or on the command line.
helm template test charts/base-aws/ -f my-values.yaml
helm template test charts/base-aws/ --set image.tag=v1.0.0

# Debug mode rendering (verbose output on errors)
helm template test charts/base-aws/ -f my-values.yaml --debug

# Lint every environment you keep under values/<project>/<service>/
for env in dev qa prod; do
  echo "=== ${env} ==="
  helm lint charts/base-aws/ -f values/my-project/admin/${env}.values.yaml
done
```

> **Note:** `base-aws` targets EKS — EFS CSI volumes, ALB ingress, IRSA service accounts, and
> optional Argo Rollouts blue-green / canary delivery. For self-managed clusters use `base` instead.

<br/>

## Schema Management

`values.schema.json` validates values at install/upgrade time. When you add or change fields in `values.yaml`, update the schema to match.

<br/>

### Auto-generate schema with helm plugin

```bash

# Install plugin
helm plugin install https://github.com/losisin/helm-values-schema-json

# Generate schema from values.yaml
cd charts/base-aws
helm schema -input values.yaml -output values.schema.json
```

<br/>

### Manual update

Edit `values.schema.json` directly when adding new fields. Key rules:
- Add new properties under the correct parent object
- Set `type`, `enum`, `minimum`/`maximum` constraints as needed
- Add to `required` array if the field must always be provided
- Run `helm lint` after changes to verify
