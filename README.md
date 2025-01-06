# Helm Base App Template

A base Helm chart template for deploying applications to Kubernetes, using ArgoCD ApplicationSet for multi-environment management.

## Directory Structure

```
helm-base-app-template
├── LICENSE
├── README.md
├── appsets
│   ├── dev-applicationset.yaml
│   ├── prod-applicationset.yaml
│   └── qa-applicationset.yaml
├── charts
│   └── base
│       ├── Chart.yaml
│       ├── base.values.yaml
│       ├── templates
│       │   ├── NOTES.txt
│       │   ├── _helpers.tpl
│       │   ├── cert-cronjob.yaml
│       │   ├── certificate.yaml
│       │   ├── configmap.yaml
│       │   ├── deployment.yaml
│       │   ├── hpa.yaml
│       │   ├── imagePullSecret.yaml
│       │   ├── ingress.yaml
│       │   ├── pv.yaml
│       │   ├── pvc.yaml
│       │   ├── service.yaml
│       │   └── serviceaccount.yaml
│       └── values.yaml
└── values
    └── somaz
        ├── admin
        │   ├── dev1.values.yaml
        │   ├── prod-a.values.yaml
        │   └── qa1.values.yaml
        ├── auth
        │   ├── dev1.values.yaml
        │   ├── prod-a.values.yaml
        │   └── qa1.values.yaml
        ├── backend
        │   ├── dev1.values.yaml
        │   ├── prod-a.values.yaml
        │   └── qa1.values.yaml
        └── batch
            ├── dev1.values.yaml
            ├── prod-a.values.yaml
            └── qa1.values.yaml
```

## Features

- **Multi-Environment Support**: Manage configurations for different environments (dev1, dev2, etc.)
- **Base Chart Template**: Standardized template for consistent application deployment
- **ArgoCD Integration**: Automated deployment management through ApplicationSet
- **Configuration Management**: Centralized configuration using Helm values
- **Infrastructure as Code**: Version-controlled infrastructure definitions

## Usage

### Prerequisites

- Kubernetes cluster
- Helm v3+
- ArgoCD installed in the cluster
- Access to container registry (configured in values)

### Configuration

1. **Base Values**: Edit `charts/base/base.values.yaml` for default configurations
2. **Environment Values**: Add environment-specific values in `values/somaz/<service>/<environment>.values.yaml`
3. **ApplicationSet**: Configure `appsets/dev-applicationset.yaml` for your environments

### Supported Resources

- Deployments
- Services
- Ingress
- ConfigMaps
- Secrets
- PersistentVolumes
- PersistentVolumeClaims
- RBAC configurations
- Certificate management

### Key Components

- **Image Management**: Private registry support with credentials
- **Storage**: Configurable persistent storage options
- **Networking**: Ingress configurations with TLS support
- **Security**: RBAC and SecurityContext settings
- **Scaling**: HPA support for automatic scaling
- **Monitoring**: Liveness and readiness probe configurations

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

