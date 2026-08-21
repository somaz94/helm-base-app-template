# Helm Base App Template

A base Helm chart template for deploying applications to Kubernetes, using ArgoCD ApplicationSet for multi-environment management.

<br/>

## Directory Structure

```
helm-base-app-template/
├── bootstrap/                        # App-of-apps control plane
│   ├── bootstrap-project.yaml        #   admin-only AppProject
│   ├── root.yaml                     #   root Application (apply once by hand)
│   └── apps/                         #   child apps managing projects/ and appsets/
├── appsets/                          # ApplicationSet definitions (examples)
│   ├── dev-my-project-applicationset.yaml
│   └── qa1-my-project-applicationset.yaml
├── charts/                           # Helm charts
│   ├── base/                         # On-premises chart (NFS, nginx ingress)
│   │   ├── templates/
│   │   ├── values.yaml
│   │   └── values.schema.json
│   └── base-aws/                     # AWS EKS chart (EFS, ALB ingress)
│       ├── templates/
│       ├── values.yaml
│       └── values.schema.json
├── values/                           # Environment-specific Helm values — you create this
│   └── {project}/
│       └── {service}/
│           └── {env}.values.yaml
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

Two example ApplicationSets ship with this template. Copy one, point `repoURL` at your
own repository, and rename `{project}` to your project.

| ApplicationSet | Environment | Chart | Services |
|----------------|-------------|-------|----------|
| dev-my-project | dev1 | base | auto-discovered from `values/my-project/*` |
| qa1-my-project | qa1 | base | `game`, `admin`, `app-admin` (explicit paths) |

<br/>

## Usage

### Adding a New Service

1. Create values files:

```bash
# Create directory
mkdir -p values/my-project/new-service

# Create environment values files (reference existing services)
cp values/my-project/admin/dev1.values.yaml values/my-project/new-service/dev1.values.yaml
# Modify image, ports, environment variables, etc.
```

2. After git push, ArgoCD automatically detects and deploys.

> **Note:** The ApplicationSet's Git Generator auto-discovers `values/{project}/*` directories, so adding a directory alone registers a new service without modifying the ApplicationSet.

### Adding a New Environment

1. Create values files:

```bash
# Add new environment values for each service
cp values/my-project/admin/dev1.values.yaml values/my-project/admin/dev2.values.yaml
# Modify for the target environment
```

2. Add the environment to the ApplicationSet's list generator.

### Validating Values Files

```bash
# Lint with chart defaults
helm lint charts/base/

# Lint with one of your values files
helm lint charts/base/ -f values/my-project/admin/dev1.values.yaml

# Strict mode lint (treats warnings as errors, validates against values.schema.json)
helm lint charts/base/ -f values/my-project/admin/dev1.values.yaml --strict

# Render templates. image.tag is required per service, so a bare render fails by
# design — supply it from your values file or on the command line.
helm template test charts/base/ -f values/my-project/admin/dev1.values.yaml
helm template test charts/base/ --set image.tag=v1.0.0

# Debug mode rendering (verbose output on errors)
helm template test charts/base/ -f values/my-project/admin/dev1.values.yaml --debug

# Lint all environments for a specific service
for env in dev1 qa1 prod; do
  echo "=== ${env} ==="
  helm lint charts/base/ -f values/my-project/admin/${env}.values.yaml
done
```

<br/>

## App-of-Apps Bootstrap

`bootstrap/` turns the `projects/` and `appsets/` trees into GitOps-managed state instead of
manifests someone has to remember to `kubectl apply`. Two files are applied by hand exactly
once — they are the entry point, so they cannot manage themselves — and everything below them
is reconciled from git afterwards.

```
bootstrap-root  (Application, applied by hand)
├── projects   (child app, sync-wave -1)  →  projects/*.yaml     → AppProjects
└── appsets    (child app, sync-wave  0)  →  appsets/*.yaml      → ApplicationSets
                                                                    └── generated Applications
```

```bash
kubectl apply -n argocd -f bootstrap/bootstrap-project.yaml
kubectl apply -n argocd -f bootstrap/root.yaml
```

The root reads `bootstrap/apps`, **not** `bootstrap/` — otherwise it would manage its own
manifest and the `bootstrap` AppProject that scopes it.

### Prune policy: the control plane is not pruned

Every layer here runs `prune: false` with `selfHeal: true`, which is the opposite of the leaf
workloads. The reason is cascade deletion:

| Layer | Prune | Why |
|-------|-------|-----|
| `bootstrap-root`, child apps | `false` | A stray prune would delete the control plane itself |
| AppProjects | `false` | Pruning a project while apps reference it freezes them all — auto-sync halts with "project does not exist" |
| ApplicationSets | `false` | `preserveResourcesOnDeletion` defaults to `false`, so deleting an appset deletes **every Application it generated** |
| Generated workload Applications | `true` | True GitOps at the leaf — these should follow git exactly |

`selfHeal` still re-applies anything drifted or hand-deleted, so the control plane converges
without ever being allowed to cascade-delete. Removing something intentionally is a deliberate
manual prune.

### Two footguns worth knowing

**Never set `directory.recurse: false` explicitly.** `false` is the ArgoCD default, so the
controller normalizes the field away on the live object. Git then has a field the live object
does not, the parent app-of-apps sees a permanent OutOfSync diff, and `selfHeal` re-syncs
forever. Omit the key instead — the child apps here do.

**Sync waves are cosmetic, not load-bearing.** `projects` at wave `-1` lands before `appsets`
at wave `0` so an appset's generated app does not briefly report "project not found". If the
order is ever violated, `selfHeal` converges anyway.

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
| ApplicationSet | `{env}-{project}-applicationset` | `dev-my-project-applicationset` |
| Application | `{env}-{project}-{service}` | `dev1-my-project-admin` |
| Namespace | `{env}-{project}` | `dev1-my-project` |
| Values file | `{env}.values.yaml` | `dev1.values.yaml` |
| Helm Release | `{env}-{project}-{service}` | `dev1-my-project-admin` |

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
