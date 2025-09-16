# Base AWS Helm Chart

A basic Helm Chart for use in AWS environments. Supports persistent storage through EFS (Elastic File System).

<br/>

## Features

- AWS EFS support
- Multiple PersistentVolume and PersistentVolumeClaim array support
- Directory separation through EFS subpath specification
- Individual mountPath configuration per PVC
- Multiple access modes (ReadWriteMany) support
- Uses existing StorageClass

<br/>

## Prerequisites

1. AWS EKS cluster
2. EFS CSI driver installation
3. EFS file system creation
4. Existing EFS StorageClass
5. Proper IAM permissions setup

<br/>

### EFS CSI Driver Installation

```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.7"
```

Or install with Helm:

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm upgrade -i aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set image.repository=602401143452.dkr.ecr.region-code.amazonaws.com/eks/aws-efs-csi-driver
```

<br/>

## Usage

<br/>

### 1. Create EFS File System

Create an EFS file system through AWS console or CLI.

```bash
aws efs create-file-system \
    --performance-mode generalPurpose \
    --tags Key=Name,Value=my-efs-filesystem
```

<br/>

### 2. Configure Values File

Configure using the `values-efs-example.yaml` file as reference:

```yaml
efs:
  persistentVolumes:
    enabled: true
    fileSystemId: "fs-1234567890abcdef0"  # Actual EFS file system ID
    storageClassName: "efs-sc"  # Use existing StorageClass
    items:
      - name: "my-app-data-pv"
        storage: "5Gi"
        volumeMode: Filesystem
        accessModes:
          - ReadWriteMany
        reclaimPolicy: Retain
        storageClassName: "efs-sc"
        subPath: "data"  # EFS internal data directory (set as volumeAttributes.path)
      - name: "my-app-logs-pv"
        storage: "5Gi"
        volumeMode: Filesystem
        accessModes:
          - ReadWriteMany
        reclaimPolicy: Retain
        storageClassName: "efs-sc"
        subPath: "logs"  # EFS internal logs directory (set as volumeAttributes.path)

  persistentVolumeClaims:
    enabled: true
    items:
      - name: "my-app-data-pvc"
        accessModes:
          - ReadWriteMany
        storageClassName: "efs-sc"
        storage: "5Gi"
        mountPath: "/app/data"  # Mount path within pod
        selector:
          volumeName: "my-app-data-pv"
      - name: "my-app-logs-pvc"
        accessModes:
          - ReadWriteMany
        storageClassName: "efs-sc"
        storage: "5Gi"
        mountPath: "/app/logs"  # Mount path within pod
        selector:
          volumeName: "my-app-logs-pv"
```

<br/>

## Configuration Options

<br/>

### PersistentVolumes Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistentVolumes.enabled` | Enable PV usage | `false` |
| `persistentVolumes.fileSystemId` | EFS file system ID (required) | `""` |
| `persistentVolumes.accessPointId` | EFS access point ID (optional) | `""` |
| `persistentVolumes.storageClassName` | Default storage class | `"efs-sc"` |

<br/>

### PV Items Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `items[].name` | PV name | - |
| `items[].storage` | Storage capacity | - |
| `items[].volumeMode` | Volume mode | `"Filesystem"` |
| `items[].accessModes` | Access modes | - |
| `items[].reclaimPolicy` | Reclaim policy | `"Retain"` |
| `items[].storageClassName` | Storage class | Inherits from parent |
| `items[].subPath` | EFS internal sub path (volumeAttributes.path) | `""` |

<br/>

### PersistentVolumeClaims Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistentVolumeClaims.enabled` | Enable PVC usage | `false` |

<br/>

### PVC Items Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `items[].name` | PVC name | - |
| `items[].accessModes` | Access modes | - |
| `items[].storageClassName` | Storage class | - |
| `items[].storage` | Storage capacity | - |
| `items[].mountPath` | Mount path within pod | - |
| `items[].subPath` | Additional sub path (optional) | `""` |
| `items[].readOnly` | Read-only flag | `false` |
| `items[].selector.volumeName` | PV name to connect | - |

## Important Notes

1. EFS file system ID must be accurate.
2. EFS CSI driver must be installed.
3. Check network policies and security group settings.
4. Directories are automatically created when using SubPath.
5. Multiple pods can access ReadWriteMany simultaneously.

<br/>

## Troubleshooting

<br/>

### When Pod is in Pending State

```bash
kubectl describe pod <pod-name>
```

Common causes:
- EFS CSI driver not installed
- Incorrect EFS file system ID
- Network connectivity issues
- Insufficient IAM permissions

<br/>

### Mount Failure

```bash
kubectl logs <pod-name>
kubectl describe pv <pv-name>
kubectl describe pvc <pvc-name>
```