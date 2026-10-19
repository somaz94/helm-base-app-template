# Base Helm Chart

On-premises Helm chart for Kubernetes applications.

<br/>

## Overview

Generic Helm chart for self-managed / on-premises Kubernetes clusters: NFS or any CSI driver for storage, nginx Ingress or Gateway API for traffic, and cert-manager integration. Used by ArgoCD ApplicationSet with the Matrix Generator pattern.

<br/>

## Templates

The [templates/](templates/) directory is the SSOT for the full set of rendered resources — the file name is the resource, so the listing is not duplicated here.

Grouped by feature:

- **Workload**: Deployment, Service, ServiceAccount, HorizontalPodAutoscaler, ConfigMap
- **Traffic**: nginx Ingress, Gateway API HTTPRoute
- **Storage**: static PersistentVolume, PersistentVolumeClaim, optional StorageClass (NFS or any CSI driver)
- **Certificates & credentials**: cert-manager Certificate with its cleanup CronJob, Docker registry pull Secret

Everything except Deployment and Service is toggled by an `enabled` flag (or a list value) in `values.yaml`.

<br/>

## Features

- **Environment injection**: `environment` value auto-injected as `ENVIRONMENT` env var to main and init containers
- **Version-based routing**: `version` label on pods, Service selector filters by version for canary/blue-green
- **Init containers**: Configurable init containers with shared volumes and env inheritance
- **EmptyDir volumes**: Ephemeral volumes with size limits and medium support
- **Any storage backend**: static PVs from an NFS export or any CSI driver, dynamic provisioning via `storageClassName`, and optional `StorageClass` creation
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
| `httproute.enabled` | `false` | Enable Gateway API HTTPRoute creation |
| `autoscaling.enabled` | `false` | Enable HPA |
| `strategy.enabled` | `false` | Enable custom deployment strategy |
| `configs.enabled` | `false` | Enable ConfigMap creation |
| `initContainers.enabled` | `false` | Enable init containers |
| `emptyDirVolumes.enabled` | `false` | Enable emptyDir volumes |
| `persistentVolumes.enabled` | `false` | Enable static PV creation |
| `storageClasses` | `[]` | Optional cluster-scoped StorageClass creation |
| `persistentVolumeClaims.enabled` | `false` | Enable PVC creation |
| `certificate.enabled` | `false` | Enable cert-manager Certificate |
| `certCleanup.enabled` | `false` | Enable cert cleanup CronJob |
| `imageCredentials.enabled` | `false` | Generate docker registry Secret (off — pull secret delivered externally via cluster-wide SealedSecret) |

This table covers the commonly used toggles only. `values.yaml` and `values.schema.json` are the SSOT for the full key set and its constraints; the table tracks them.

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

## Storage

`persistentVolumes.items[]` takes a `source` of `nfs` (the default, matching this chart's
original behaviour) or `csi`. Existing NFS values files need no change.

| Field | Applies to | Description |
|-------|-----------|-------------|
| `source` | both | `nfs` (default) or `csi` |
| `server` / `path` | `nfs` | The export to mount |
| `driver` / `volumeHandle` | `csi` | Driver name and its volume identifier |
| `volumeAttributes` | `csi` | Driver-specific attributes |
| `nodeStageSecretRef` | `csi` | Per-volume credentials, where the driver needs them |
| `mountOptions`, `readOnly`, `fsType` | both | Passed through as-is |

Dynamic provisioning needs no PV at all — declare a PVC with a `storageClassName` and let the
provisioner create the volume. `storageClasses` can create the classes themselves; note that
`StorageClass` is **cluster-scoped**, so an ArgoCD AppProject delivering it must whitelist
`storage.k8s.io/StorageClass` or the whole Application is rejected.

<br/>

## Validation

```bash
# Lint with chart defaults
helm lint charts/base/

# Lint with your own values file
helm lint charts/base/ -f my-values.yaml

# Strict mode lint (treats warnings as errors, validates against values.schema.json)
helm lint charts/base/ -f my-values.yaml --strict

# Render templates. image.tag is required per service, so a bare render fails by
# design — supply it from your values file or on the command line.
helm template test charts/base/ -f my-values.yaml
helm template test charts/base/ --set image.tag=v1.0.0

# Debug mode rendering (verbose output on errors)
helm template test charts/base/ -f my-values.yaml --debug

# Lint every environment you keep under values/<project>/<service>/
for env in dev qa prod; do
  echo "=== ${env} ==="
  helm lint charts/base/ -f values/my-project/admin/${env}.values.yaml
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
