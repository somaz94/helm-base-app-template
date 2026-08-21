# Base Helm Chart

On-premises Helm chart for ExampleProject/SecondaryProject applications.

<br/>

## Overview

Generic Helm chart designed for on-premises Kubernetes clusters with NFS storage, nginx ingress, and cert-manager integration. Used by ArgoCD ApplicationSet with Matrix Generator pattern.

<br/>

## Templates

| Template | Resource | Description |
|----------|----------|-------------|
| `deployment.yaml` | Deployment | Main workload with init containers, env injection, volume mounts |
| `service.yaml` | Service | ClusterIP/NodePort/LoadBalancer with version-based selector |
| `ingress.yaml` | Ingress | nginx ingress with TLS support |
| `serviceaccount.yaml` | ServiceAccount | Optional SA with annotations |
| `hpa.yaml` | HorizontalPodAutoscaler | CPU/memory-based autoscaling (v2) |
| `configmap.yaml` | ConfigMap | Multiple ConfigMaps with envFrom injection |
| `pv.yaml` | PersistentVolume | NFS-backed PVs (multiple items) |
| `pvc.yaml` | PersistentVolumeClaim | PVCs with optional PV selector binding |
| `imagePullSecret.yaml` | Secret | Docker registry credentials (dockerconfigjson) |
| `certificate.yaml` | Certificate | cert-manager Certificate (Route53/CloudDNS) |
| `cert-cronjob.yaml` | CronJob | Daily cleanup of old CertificateRequests and Jobs |
| `_helpers.tpl` | - | Helper templates (name, labels, imagePullSecret) |
| `NOTES.txt` | - | Post-install instructions |

<br/>

## Features

- **Environment injection**: `environment` value auto-injected as `ENVIRONMENT` env var to main and init containers
- **Version-based routing**: `version` label on pods, Service selector filters by version for canary/blue-green
- **Init containers**: Configurable init containers with shared volumes and env inheritance
- **EmptyDir volumes**: Ephemeral volumes with size limits and medium support
- **Multiple PV/PVC**: Array-based creation of NFS PersistentVolumes and PersistentVolumeClaims
- **Extra volumes**: Escape hatch for volumes/mounts not covered by built-in types
- **ConfigMap envFrom**: Multiple ConfigMaps auto-loaded as environment variables
- **cert-manager**: Certificate resource with automated cleanup CronJob
- **Schema validation**: `values.schema.json` validates input values

<br/>

## Values

<br/>

### Required

| Parameter | Type | Description |
|-----------|------|-------------|
| `replicaCount` | int | Number of pod replicas |
| `image.repository` | string | Container image repository |
| `image.pullPolicy` | string | Image pull policy (`Always`, `IfNotPresent`, `Never`) |
| `service.type` | string | Service type (`ClusterIP`, `NodePort`, `LoadBalancer`) |
| `service.port` | int | Service port |

<br/>

### Common Overrides

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environment` | `""` | Environment name → `ENVIRONMENT` env var |
| `version` | `""` | Version label for routing |
| `image.tag` | `""` | Image tag — required per service (render fails if unset) |
| `service.targetPort` | `8080` | Container port |
| `ingress.enabled` | `false` | Enable ingress |
| `autoscaling.enabled` | `false` | Enable HPA |
| `strategy.enabled` | `false` | Enable custom deployment strategy |
| `configs.enabled` | `false` | Enable ConfigMap creation |
| `initContainers.enabled` | `false` | Enable init containers |
| `emptyDirVolumes.enabled` | `false` | Enable emptyDir volumes |
| `persistentVolumes.enabled` | `false` | Enable NFS PV creation |
| `persistentVolumeClaims.enabled` | `false` | Enable PVC creation |
| `certificate.enabled` | `false` | Enable cert-manager Certificate |
| `certCleanup.enabled` | `false` | Enable cert cleanup CronJob |
| `imageCredentials.enabled` | `false` | Generate docker registry Secret (off — pull secret delivered externally via cluster-wide SealedSecret) |

<br/>

## Usage with ApplicationSet

This chart is referenced by ApplicationSet definitions:

```yaml
source:
  path: charts/base
  helm:
    valueFiles:
      - '../../values/{project}/{service}/{env}.values.yaml'
```

`values.yaml` provides defaults; environment-specific values files override per deployment.

<br/>

## Validation

```bash
# Lint with default values
helm lint charts/base/

# Lint with environment values
helm lint charts/base/ -f values/example-project/game/dev1.values.yaml

# Strict mode lint (treats warnings as errors)
helm lint charts/base/ -f values/example-project/game/dev1.values.yaml --strict

# Render templates
helm template test charts/base/ -f values/example-project/game/dev1.values.yaml

# Debug mode rendering (verbose output on errors)
helm template test charts/base/ -f values/example-project/game/dev1.values.yaml --debug

# Lint all environments for a specific service
for env in alpha dev1 qa1; do
  echo "=== ${env} ==="
  helm lint charts/base/ -f values/example-project/game/${env}.values.yaml
done
```

<br/>

## Schema Management

`values.schema.json` validates values at install/upgrade time. When you add or change fields in `values.yaml`, update the schema to match.

<br/>

### Auto-generate schema with helm plugin

```bash

# Install plugin
helm plugin install https://github.com/losisin/helm-values-schema-json

# Generate schema from values.yaml
cd charts/base
helm schema -input values.yaml -output values.schema.json
```

<br/>

### Manual update

Edit `values.schema.json` directly when adding new fields. Key rules:
- Add new properties under the correct parent object
- Set `type`, `enum`, `minimum`/`maximum` constraints as needed
- Add to `required` array if the field must always be provided
- Run `helm lint` after changes to verify
