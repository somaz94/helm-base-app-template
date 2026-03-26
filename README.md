# Helm Base App Template

A base Helm chart template for deploying applications to Kubernetes, using ArgoCD ApplicationSet for multi-environment management.

<br/>

## Directory Structure

```
helm-base-app-template/
├── appsets/                          # ApplicationSet definitions
│   ├── dev-applicationset.yaml
│   ├── qa-applicationset.yaml
│   ├── alpha-applicationset.yaml
│   └── prod-applicationset.yaml
├── charts/                           # Helm charts
│   ├── base/                         # On-premises chart (NFS, nginx ingress)
│   │   ├── templates/
│   │   ├── values.yaml
│   │   └── values.schema.json
│   └── base-aws/                     # AWS EKS chart (EFS, ALB ingress)
│       ├── templates/
│       ├── values.yaml
│       └── values.schema.json
├── values/                           # Environment-specific Helm values
│   └── somaz/
│       ├── admin/
│       ├── auth/
│       ├── backend/
│       └── batch/
├── .github/workflows/                # CI/CD (GitLab mirror)
└── LICENSE
```

<br/>

## Architecture

### ApplicationSet Pattern

Uses Matrix Generator combining cluster info + Git directory discovery.

```
ApplicationSet (Matrix Generator)
├── List Generator         → Defines cluster URL, project name, environment
└── Git Generator          → Auto-discovers values/{project}/* directories
    └── Template
        ├── App Name       → {environment}-{project}-{service}
        ├── Source          → charts/base + values/{project}/{service}/{env}.values.yaml
        ├── Destination     → Cluster URL + {environment}-{project} namespace
        └── Sync Policy    → Auto Prune + Self-Heal
```

### Deployment Flow

```
Modify values file → Git Push → ArgoCD detects → Helm rendering → Auto deploy to K8s
```

<br/>

## Helm Charts

### base (On-premises)

Helm chart for on-premises clusters with NFS storage and nginx ingress. See [charts/base/](charts/base/) for chart details.

| Template | Description |
|----------|-------------|
| deployment.yaml | Deployment (init containers, env injection, volume mounts) |
| service.yaml | Service (version-based selector) |
| ingress.yaml | Ingress (nginx) |
| configmap.yaml | ConfigMap (multiple creation, envFrom injection) |
| hpa.yaml | Horizontal Pod Autoscaler (v2) |
| pv.yaml / pvc.yaml | NFS PersistentVolume (multiple items) |
| certificate.yaml | cert-manager Certificate (Route53/CloudDNS) |
| cert-cronjob.yaml | Certificate cleanup CronJob |
| serviceaccount.yaml | ServiceAccount |
| imagePullSecret.yaml | Docker registry Secret |

<br/>

### base-aws (AWS EKS)

Helm chart for AWS EKS environments with EFS storage and ALB ingress. See [charts/base-aws/](charts/base-aws/) for chart details.

| Template | Description |
|----------|-------------|
| deployment.yaml | Deployment (EFS mounts, env injection) |
| service.yaml | Service (version-based selector) |
| ingress.yaml | Ingress (ALB, Client-Version header routing) |
| ingress-health.yaml | Health check Ingress |
| ingress-review.yaml | App store review Ingress |
| ingress-api-docs.yaml | API docs Ingress |
| configmap.yaml | ConfigMap (multiple creation, envFrom injection) |
| hpa.yaml | Horizontal Pod Autoscaler (v2) |
| efs-pv.yaml / efs-pvc.yaml | EFS CSI PersistentVolume |
| serviceaccount.yaml | ServiceAccount (IRSA support) |

<br/>

## Projects and Environments

### ApplicationSet List

| ApplicationSet | Environment | Chart | Services |
|----------------|-------------|-------|----------|
| dev-somaz | dev1, dev2 | base | admin, auth, backend, batch |
| qa-somaz | qa1, qa2 | base | admin, auth, backend, batch |
| alpha-somaz | alpha | base-aws | admin, auth, backend, batch |
| prod-somaz | prod-a, prod-b | base | admin, auth, backend, batch |

<br/>

## Usage

### Adding a New Service

1. Create values files:

```bash
# Create directory
mkdir -p values/somaz/new-service

# Create environment values files (reference existing services)
cp values/somaz/admin/dev1.values.yaml values/somaz/new-service/dev1.values.yaml
# Modify image, ports, environment variables, etc.
```

2. After git push, ArgoCD automatically detects and deploys.

> **Note:** The ApplicationSet's Git Generator auto-discovers `values/{project}/*` directories, so adding a directory alone registers a new service without modifying the ApplicationSet.

### Adding a New Environment

1. Create values files:

```bash
# Add new environment values for each service
cp values/somaz/admin/dev1.values.yaml values/somaz/admin/dev2.values.yaml
# Modify for the target environment
```

2. Add the environment to the ApplicationSet's list generator.

### Validating Values Files

```bash
# Lint with default values
helm lint charts/base/

# Lint with environment values
helm lint charts/base/ -f values/somaz/admin/dev1.values.yaml

# Strict mode lint (treats warnings as errors)
helm lint charts/base/ -f values/somaz/admin/dev1.values.yaml --strict

# Render templates
helm template test charts/base/ -f values/somaz/admin/dev1.values.yaml

# Debug mode rendering (verbose output on errors)
helm template test charts/base/ -f values/somaz/admin/dev1.values.yaml --debug

# Lint all environments for a specific service
for env in dev1 qa1 prod-a; do
  echo "=== ${env} ==="
  helm lint charts/base/ -f values/somaz/admin/${env}.values.yaml
done
```

<br/>

## Sync Policy

Sync policies applied to all ApplicationSets:

| Policy | Value | Description |
|--------|-------|-------------|
| `automated.prune` | `true` | Auto-remove resources deleted from Git |
| `automated.selfHeal` | `true` | Auto-restore manual changes |
| `CreateNamespace` | `true` | Auto-create namespaces |
| `ApplyOutOfSyncOnly` | `true` | Only apply changed resources |

<br/>

## Naming Convention

| Item | Pattern | Example |
|------|---------|---------|
| ApplicationSet | `{env}-{project}-applicationset` | `dev-somaz-applicationset` |
| Application | `{env}-{project}-{service}` | `dev1-somaz-admin` |
| Namespace | `{env}-{project}` | `dev1-somaz` |
| Values file | `{env}.values.yaml` | `dev1.values.yaml` |
| Helm Release | `{env}-{project}-{service}` | `dev1-somaz-admin` |

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

When editing `values.schema.json` manually:
- Add new properties under the correct parent object
- Set `type`, `enum`, `minimum`/`maximum` constraints
- Add required fields to the `required` array
- Validate changes with `helm lint`

<br/>

## Troubleshooting

| Symptom | Resolution |
|---------|------------|
| Application stuck in OutOfSync | Run Sync from ArgoCD UI or check values files |
| New service not detected | Verify `values/{project}/{service}/` directory and `{env}.values.yaml` exist |
| Helm rendering error | Validate locally with `helm lint` and `helm template` |
| Namespace creation failure | Check `CreateNamespace=true` option in ApplicationSet |
| ImagePullBackOff | Verify image pull Secret exists in the target namespace |

<br/>

## References

- [ArgoCD ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [Helm Documentation](https://helm.sh/docs/)
- [ArgoCD Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)

<br/>

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
