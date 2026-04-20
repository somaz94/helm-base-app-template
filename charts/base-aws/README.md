# Base-AWS Helm Chart

AWS EKS Helm chart for TertiaryProject applications.

<br/>

## Overview

Specialized Helm chart for AWS EKS clusters with EFS CSI storage, AWS ALB ingress (including header-based routing), and multiple ingress types. Used by ArgoCD ApplicationSet with Matrix Generator pattern.

<br/>

## Templates

| Template | Resource | Description |
|----------|----------|-------------|
| `deployment.yaml` | Deployment | Main workload with EFS mounts, env injection |
| `service.yaml` | Service | ClusterIP/NodePort/LoadBalancer with version selector |
| `ingress.yaml` | Ingress | Main ALB ingress with Client-Version header routing |
| `ingress-review.yaml` | Ingress | iOS app review traffic with version-specific routing |
| `ingress-health.yaml` | Ingress | Dedicated health check endpoint (no header conditions) |
| `ingress-api-docs.yaml` | Ingress | API documentation endpoint |
| `serviceaccount.yaml` | ServiceAccount | Optional SA with IRSA annotations |
| `hpa.yaml` | HorizontalPodAutoscaler | CPU/memory-based autoscaling (v2) |
| `configmap.yaml` | ConfigMap | Multiple ConfigMaps with envFrom injection |
| `efs-pv.yaml` | PersistentVolume | EFS CSI-backed PVs with Access Point support |
| `efs-pvc.yaml` | PersistentVolumeClaim | PVCs with optional static PV binding |
| `_helpers.tpl` | - | Helper templates (name, labels) |
| `NOTES.txt` | - | Post-install instructions |

<br/>

## Features

- **AWS ALB Ingress**: 4 ingress types (main, review, health, api-docs) with shared ALB group
- **Client-Version routing**: Header-based routing via ALB conditions/actions annotations
- **EFS CSI storage**: PersistentVolumes with EFS file system ID and Access Point support
- **Environment injection**: `environment` value auto-injected as `ENVIRONMENT` env var
- **Version-based routing**: `version` label on pods for canary/blue-green deployments
- **ConfigMap envFrom**: Multiple ConfigMaps auto-loaded as environment variables
- **IRSA support**: ServiceAccount annotations for IAM Roles for Service Accounts
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
| `image.tag` | `""` | Image tag (defaults to `appVersion`) |
| `service.targetPort` | `8080` | Container port |
| `ingress.enabled` | `false` | Enable main ALB ingress |
| `ingressReview.enabled` | `false` | Enable review ingress (iOS) |
| `ingressHealth.enabled` | `false` | Enable health check ingress |
| `ingressApiDocs.enabled` | `false` | Enable API docs ingress |
| `autoscaling.enabled` | `false` | Enable HPA |
| `strategy.enabled` | `false` | Enable custom deployment strategy |
| `configs.enabled` | `false` | Enable ConfigMap creation |
| `efs.persistentVolumes.enabled` | `false` | Enable EFS PV creation |
| `efs.persistentVolumeClaims.enabled` | `false` | Enable EFS PVC creation |

<br/>

### EFS Configuration

Each PV item requires:

| Parameter | Description |
|-----------|-------------|
| `fileSystemId` | EFS file system ID (required, e.g., `fs-0123456789abcdef0`) |
| `accessPointId` | EFS Access Point ID (optional, e.g., `fsap-0123456789abcdef0`) |
| `storage` | Storage capacity (e.g., `5Gi`) |
| `storageClassName` | Storage class (e.g., `efs-sc`) |

<br/>

### ALB Ingress Configuration

Key ALB annotations used:

| Annotation | Description |
|------------|-------------|
| `alb.ingress.kubernetes.io/scheme` | `internet-facing` or `internal` |
| `alb.ingress.kubernetes.io/target-type` | `ip` (required for Fargate/VPC CNI) |
| `alb.ingress.kubernetes.io/group.name` | Shared ALB group name |
| `alb.ingress.kubernetes.io/group.order` | Priority within ALB group (1-1000) |
| `alb.ingress.kubernetes.io/certificate-arn` | ACM certificate ARN for TLS |
| `alb.ingress.kubernetes.io/conditions.*` | Header/path-based routing conditions |
| `alb.ingress.kubernetes.io/actions.*` | Target group forwarding actions |

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
# Lint with default values
helm lint charts/base-aws/

# Lint with environment values (tertiary-project project, deprecated)
helm lint charts/base-aws/ -f values/tertiary-project/game/alpha.values.yaml

# Strict mode lint (treats warnings as errors)
helm lint charts/base-aws/ -f values/tertiary-project/game/alpha.values.yaml --strict

# Render templates
helm template test charts/base-aws/

# Render with custom values (tertiary-project project, deprecated)
helm template test charts/base-aws/ -f values/tertiary-project/game/alpha.values.yaml

# Debug mode rendering (verbose output on errors)
helm template test charts/base-aws/ -f values/tertiary-project/game/alpha.values.yaml --debug

# Lint all environments for a specific service (tertiary-project project, deprecated)
for env in alpha review; do
  echo "=== ${env} ==="
  helm lint charts/base-aws/ -f values/tertiary-project/game/${env}.values.yaml
done
```

> **Note:** The `base-aws` chart was built for the tertiary-project project, which is currently deprecated.

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
