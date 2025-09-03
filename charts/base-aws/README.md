# Base AWS Helm Chart

AWS 환경에서 사용할 수 있는 기본 Helm Chart입니다. EFS(Elastic File System)를 통한 영구 스토리지를 지원합니다.

<br/>

## 기능

- AWS EFS 지원
- 여러 PersistentVolume 및 PersistentVolumeClaim 배열 지원
- EFS 서브패스 지정으로 디렉토리 분리
- PVC별 mountPath 개별 설정
- 다중 접근 모드 (ReadWriteMany) 지원
- 기존 StorageClass 사용

<br/>

## 전제 조건

1. AWS EKS 클러스터
2. EFS CSI 드라이버 설치
3. EFS 파일 시스템 생성
4. 기존 EFS StorageClass 존재
5. 적절한 IAM 권한 설정

<br/>

### EFS CSI 드라이버 설치

```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.7"
```

또는 Helm으로 설치:

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm upgrade -i aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set image.repository=602401143452.dkr.ecr.region-code.amazonaws.com/eks/aws-efs-csi-driver
```

<br/>

## 사용법

<br/>

### 1. EFS 파일 시스템 생성

AWS 콘솔 또는 CLI를 통해 EFS 파일 시스템을 생성합니다.

```bash
aws efs create-file-system \
    --performance-mode generalPurpose \
    --tags Key=Name,Value=my-efs-filesystem
```

<br/>

### 2. Values 파일 설정

`values-efs-example.yaml` 파일을 참고하여 설정합니다:

```yaml
efs:
  persistentVolumes:
    enabled: true
    fileSystemId: "fs-1234567890abcdef0"  # 실제 EFS 파일 시스템 ID
    storageClassName: "efs-sc"  # 기존 StorageClass 사용
    items:
      - name: "my-app-data-pv"
        storage: "5Gi"
        volumeMode: Filesystem
        accessModes:
          - ReadWriteMany
        reclaimPolicy: Retain
        storageClassName: "efs-sc"
        subPath: "data"  # EFS 내부 data 디렉토리 (volumeAttributes.path로 설정)
      - name: "my-app-logs-pv"
        storage: "5Gi"
        volumeMode: Filesystem
        accessModes:
          - ReadWriteMany
        reclaimPolicy: Retain
        storageClassName: "efs-sc"
        subPath: "logs"  # EFS 내부 logs 디렉토리 (volumeAttributes.path로 설정)

  persistentVolumeClaims:
    enabled: true
    items:
      - name: "my-app-data-pvc"
        accessModes:
          - ReadWriteMany
        storageClassName: "efs-sc"
        storage: "5Gi"
        mountPath: "/app/data"  # Pod 내 마운트 경로
        selector:
          volumeName: "my-app-data-pv"
      - name: "my-app-logs-pvc"
        accessModes:
          - ReadWriteMany
        storageClassName: "efs-sc"
        storage: "5Gi"
        mountPath: "/app/logs"  # Pod 내 마운트 경로
        selector:
          volumeName: "my-app-logs-pv"
```

<br/>

## 설정 옵션

<br/>

### PersistentVolumes 설정

| 파라미터 | 설명 | 기본값 |
|----------|------|--------|
| `persistentVolumes.enabled` | PV 사용 여부 | `false` |
| `persistentVolumes.fileSystemId` | EFS 파일 시스템 ID (필수) | `""` |
| `persistentVolumes.accessPointId` | EFS 접근 포인트 ID (선택) | `""` |
| `persistentVolumes.storageClassName` | 기본 스토리지 클래스 | `"efs-sc"` |

<br/>

### PV Items 설정

| 파라미터 | 설명 | 기본값 |
|----------|------|--------|
| `items[].name` | PV 이름 | - |
| `items[].storage` | 스토리지 용량 | - |
| `items[].volumeMode` | 볼륨 모드 | `"Filesystem"` |
| `items[].accessModes` | 접근 모드 | - |
| `items[].reclaimPolicy` | 회수 정책 | `"Retain"` |
| `items[].storageClassName` | 스토리지 클래스 | 상위 설정 상속 |
| `items[].subPath` | EFS 내부 서브 경로 (volumeAttributes.path) | `""` |

<br/>

### PersistentVolumeClaims 설정

| 파라미터 | 설명 | 기본값 |
|----------|------|--------|
| `persistentVolumeClaims.enabled` | PVC 사용 여부 | `false` |

<br/>

### PVC Items 설정

| 파라미터 | 설명 | 기본값 |
|----------|------|--------|
| `items[].name` | PVC 이름 | - |
| `items[].accessModes` | 접근 모드 | - |
| `items[].storageClassName` | 스토리지 클래스 | - |
| `items[].storage` | 스토리지 용량 | - |
| `items[].mountPath` | Pod 내 마운트 경로 | - |
| `items[].subPath` | 추가 서브 경로 (선택) | `""` |
| `items[].readOnly` | 읽기 전용 여부 | `false` |
| `items[].selector.volumeName` | 연결할 PV 이름 | - |

## 주의사항

1. EFS 파일 시스템 ID는 반드시 정확해야 합니다.
2. EFS CSI 드라이버가 설치되어 있어야 합니다.
3. 네트워크 정책 및 보안 그룹 설정을 확인하세요.
4. SubPath를 사용할 때 디렉토리가 자동으로 생성됩니다.
5. 여러 Pod에서 동시에 ReadWriteMany 접근이 가능합니다.

<br/>

## 트러블슈팅

<br/>

### Pod가 Pending 상태인 경우

```bash
kubectl describe pod <pod-name>
```

일반적인 원인:
- EFS CSI 드라이버 미설치
- EFS 파일 시스템 ID 오류
- 네트워크 연결 문제
- IAM 권한 부족

<br/>

### 마운트 실패 시

```bash
kubectl logs <pod-name>
kubectl describe pv <pv-name>
kubectl describe pvc <pvc-name>
```
