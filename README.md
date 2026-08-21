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
│   ├── dev-my-project-applicationset.yaml    # directory generator, globbed
│   ├── qa-my-project-applicationset.yaml     # directory generator, enumerated
│   └── prod-my-project-applicationset.yaml   # file generator, cloud chart
├── charts/                           # Helm charts — one per target platform
│   ├── base/                         # Self-managed / on-premises (NFS, nginx, Gateway API)
│   ├── base-aws/                     # AWS EKS (EFS + any CSI, ALB, IRSA)
│   ├── base-azure/                   # Azure AKS (Azure Files/Disk, AGIC, Workload Identity)
│   └── base-gcp/                     # GCP GKE (Filestore/PD, GKE Ingress, Workload Identity)
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

Uses Matrix Generator combining cluster info + Git discovery.

```
ApplicationSet (Matrix Generator)
├── List Generator         → Defines cluster URL, project name, environment
└── Git Generator          → Discovers services under values/{project}/
    └── Template
        ├── App Name       → {environment}-{project}-{service}
        ├── Source          → charts/<chart> + values/{project}/{service}/{env}.values.yaml
        ├── Destination     → Cluster URL + {environment}-{project} namespace
        └── Sync Policy    → Auto Prune + Self-Heal
```

The Git half has two generator kinds — directory and file — and the directory one is used
in two shapes. The choice is not cosmetic:

| Form | Matches | Use when |
|------|---------|----------|
| `directories:` globbed (`values/{project}/*`) | every service directory | the environment should pick up new services on its own |
| `directories:` enumerated | only the listed directories | a gated environment whose contents must stay a reviewed git change |
| `files:` (`values/{project}/*/{env}.values.yaml`) | only services that have this env's values file | a service should opt in per environment |

**A file generator needs an explicit `_deprecated` exclude; a directory generator does not.**
Directory globs match only the immediate children of the path, so a retired
`values/{project}/{service}/_deprecated/` sits one level too deep to be matched. A file glob
crosses directory boundaries, reaches that file, and emits a broken Application named after
`_deprecated`. Every file generator here therefore carries:

```yaml
- path: '**/_deprecated/**'
  exclude: true
```

**Deleting an ApplicationSet deletes its Applications.** `spec.syncPolicy.preserveResourcesOnDeletion`
defaults to `false`, so removing an appset file cascades down to every workload it generated.
Note that the field lives on the ApplicationSet's own `spec.syncPolicy`, not on the
`template`'s — putting it under the template is silently the wrong object.

### Deployment Flow

```
Modify values file → Git Push → ArgoCD detects → Helm rendering → Auto deploy to K8s
```

<br/>

## Charts

Four charts share one shape — the same values surface, the same templates, the same Argo
Rollouts / PDB / ExternalSecret / Gateway API features — and differ only in their platform
defaults. Pick by where the cluster runs, then read that chart's own README for its template
list and values reference; this page deliberately does not duplicate them.

| Chart | Version | Platform | Ingress | Storage | Identity |
|-------|---------|----------|---------|---------|----------|
| [`base`](charts/base/) | `1.0.0` | Self-managed / on-prem | nginx, Gateway API | NFS, any CSI | — |
| [`base-aws`](charts/base-aws/) | `1.0.0` | AWS EKS | ALB, Gateway API | EFS + any CSI | IRSA |
| [`base-azure`](charts/base-azure/) | `0.1.0` | Azure AKS | Application Gateway (AGIC), Gateway API | Azure Files / Disk + any CSI | Entra Workload Identity |
| [`base-gcp`](charts/base-gcp/) | `0.1.0` | GCP GKE | GKE Ingress + BackendConfig/FrontendConfig, Gateway API | Filestore / PD + any CSI | GKE Workload Identity |

`base` and `base-aws` are at `1.0.0` — they were extracted from charts running in production.
`base-azure` and `base-gcp` sit at `0.1.0` deliberately: they lint and render, but no cluster has
exercised their AGIC annotations, Filestore `volumeHandle` syntax, or BackendConfig wiring yet.
They graduate to `1.0.0` once someone runs them for real.

### Storage is driver-neutral everywhere

`storage.persistentVolumes.items[]` (`efs.persistentVolumes.items[]` on `base-aws`, kept for
backward compatibility) takes a `source` of `csi` or `nfs`. Every CSI driver works through the
same fields — `driver`, `volumeHandle`, `volumeAttributes`, `nodeStageSecretRef`, `mountOptions`
— so EFS, Azure Files, Azure Disk, Filestore, Persistent Disk and plain NFS all render from one
template. Dynamic provisioning needs no PV at all: declare a PVC with a `storageClassName`.

`storageClasses` optionally creates the StorageClasses too. That resource is **cluster-scoped**,
so an ArgoCD AppProject delivering it must whitelist it or the whole Application rolls back:

```yaml
clusterResourceWhitelist:
  - group: storage.k8s.io
    kind: StorageClass
```

### Ingress is controller-neutral everywhere

`ingress.className` + `ingress.annotations` drive any controller — ALB, AGIC, GKE Ingress,
nginx, Traefik. Each chart's `values.yaml` documents its platform's annotation set. For
Gateway API, use `httproute.*` instead, with an optional companion HTTPS-redirect route.

<br/>

## Projects and Environments

### ApplicationSet List

Three example ApplicationSets ship with this template, one per generator form. Copy the one
whose discovery behavior you want, point `repoURL` at your own repository, and rename
`{project}` to your project.

| ApplicationSet | Environment | Chart | Generator | Services |
|----------------|-------------|-------|-----------|----------|
| dev-my-project | dev | base | directory, globbed | auto-discovered from `values/my-project/*` |
| qa-my-project | qa | base | directory, enumerated | `api`, `admin`, `worker` |
| prod-my-project | prod | base-aws | file | whichever have a `prod.values.yaml` |

The `prod` example is the cloud-chart one: same file, pointed at an EKS cluster and
`charts/base-aws`. Swapping in `base-azure` or `base-gcp` changes only the chart path.

<br/>

## Usage

### Adding a New Service

1. Create values files:

```bash
# Create directory
mkdir -p values/my-project/new-service

# Create environment values files (reference existing services)
cp values/my-project/admin/dev.values.yaml values/my-project/new-service/dev.values.yaml
# Modify image, ports, environment variables, etc.
```

2. After git push, ArgoCD automatically detects and deploys.

> **Note:** This is true for a globbed directory generator (the `dev` example) — the directory alone registers the service. The `qa` example enumerates its directories on purpose, so a new service reaches it only when you add the path there; the `prod` example needs the service to have a `prod.values.yaml`.

### Adding a New Environment

1. Create values files:

```bash
# Add new environment values for each service
cp values/my-project/admin/dev.values.yaml values/my-project/admin/stg.values.yaml
# Modify for the target environment
```

2. Copy an ApplicationSet, rename it `{env}-{project}-applicationset`, and set the new
   `environment` in its list generator. One appset per environment keeps the name, the
   generated Application names and the namespace consistent — a single appset can serve
   several environments from one list generator, but then its own name can no longer
   follow the convention.

### Validating Values Files

```bash
# Lint with chart defaults
helm lint charts/base/

# Lint with one of your values files
helm lint charts/base/ -f values/my-project/admin/dev.values.yaml

# Strict mode lint (treats warnings as errors, validates against values.schema.json)
helm lint charts/base/ -f values/my-project/admin/dev.values.yaml --strict

# Render templates. image.tag is required per service, so a bare render fails by
# design — supply it from your values file or on the command line.
helm template test charts/base/ -f values/my-project/admin/dev.values.yaml
helm template test charts/base/ --set image.tag=v1.0.0

# Debug mode rendering (verbose output on errors)
helm template test charts/base/ -f values/my-project/admin/dev.values.yaml --debug

# Lint all environments for a specific service
for env in dev qa prod; do
  echo "=== ${env} ==="
  helm lint charts/base/ -f values/my-project/admin/${env}.values.yaml
done
```

<br/>

## Validating the charts

`scripts/validate-charts.sh` checks every chart against **real Kubernetes API schemas** without
needing a cloud account. It stands up a throwaway `kind` cluster, installs the Gateway API,
Argo Rollouts and External Secrets CRDs, and runs `kubectl apply --dry-run=server` over each
render path — so the API server itself rejects wrong apiVersions, unknown fields and bad types.

```bash
scripts/validate-charts.sh          # creates and deletes the kind cluster
scripts/validate-charts.sh --keep   # leaves it running for a faster second pass
```

GKE's `BackendConfig` and `FrontendConfig` are installed by the managed control plane, so `kind`
cannot provide them. Those two kinds are withheld from the API server and validated against the
published CRD catalog with `kubeconform` instead.

> **What this cannot catch:** ingress annotations. `appgw.ingress.kubernetes.io/health-probe-path`
> or `networking.gke.io/managed-certificates` are entries in a `map[string]string` — a typo is
> valid to every schema there is. The same goes for the *format* of a CSI `volumeHandle`. Those
> are settled only by running on the real platform, which is why `base-azure` and `base-gcp` sit
> at `0.1.0`.

### Smoke-testing on a real GKE cluster

`scripts/gke-smoke.sh` closes that gap for `base-gcp`. It creates a throwaway Autopilot cluster,
installs the chart, and then checks what GKE *did* rather than what it accepted:

```bash
scripts/gke-smoke.sh --project MY_PROJECT --region us-central1
```

| Check | What a failure means |
|-------|----------------------|
| `BackendConfig` / `FrontendConfig` exist | the GKE CRDs rejected the object |
| Service carries `cloud.google.com/backend-config` | the annotation key is wrong, so the LB silently uses a default health check |
| Ingress gets an external address | `kubernetes.io/ingress.class` is wrong and nothing provisions |
| backends report `HEALTHY` | the health check in force is not the one the BackendConfig asked for |
| PVC reaches `Bound` | `pd.csi` dynamic provisioning is broken |
| `HTTP 200` through the LB | traffic does not actually reach the pods |

It tears the cluster down on exit (`--keep` to keep it) and restores your previous kube context.
Filestore, managed certificates, Cloud Armor and IAP stay unverified — each needs paid
infrastructure beyond a smoke test.

**This script has not been run.** No GKE project is available to this repository's authors, and
`base-azure` has no equivalent for the same reason. Where a real cluster was out of reach, every
annotation key and CSI `volumeHandle` format was instead cross-checked against the upstream
project that consumes it — see [charts/VERIFICATION.md](charts/VERIFICATION.md) for the results
and for what remains untested.

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
| Application | `{env}-{project}-{service}` | `dev-my-project-admin` |
| Namespace | `{env}-{project}` | `dev-my-project` |
| Values file | `{env}.values.yaml` | `dev.values.yaml` |
| Helm Release | `{env}-{project}-{service}` | `dev-my-project-admin` |

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
