# MLOps Manifest Deployment Guide

## 1. Prerequisites

```bash
# ArgoCD CLI (optional)
curl -sSL -o argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/download/stable/argocd-linux-amd64
sudo install -m 755 argocd-linux-amd64 /usr/local/bin/argocd
```

---

## 2. Cài đặt K3s

```bash
curl -sfL https://get.k3s.io | sh -
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl get nodes
```

---

## 3. Cài đặt ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

kubectl patch deployment argocd-server -n argocd \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","command":["argocd-server","--insecure"]}]}}}}'

kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

---

## 4. Cài đặt Kubeflow Pipelines (Kustomize)

Dùng cách deploy chuẩn của Kubeflow bằng Kustomize command line:

```bash
export PIPELINE_VERSION=2.15.0
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=$PIPELINE_VERSION" 

# mở port 9000 trỏ về 8333 do seaweedfs dùng cổng 8333
k3s kubectl patch svc seaweedfs -n kubeflow --type='json' -p='[{"op": "add", "path": "/spec/ports/-", "value": {"name": "s3-minio-compat", "port": 9000, "targetPort": 8333}}]'

```

---

## 5. Token cho GitHub Actions ARC Runner

```bash
# Tao namespace de chua secret truoc khi ArgoCD cai ARC
kubectl create namespace actions-runner-system

# Bom token vao secret
kubectl create secret generic controller-manager \
    -n actions-runner-system \
    --from-literal=github_token="THAY_CHUOI_GHP_XXXX_CUA_BAN_VAO_DAY"
```

---

## 6. MLOps Endpoints (QUAN TRỌNG)

Toàn bộ hệ thống giờ đã gỡ bỏ hoàn toàn `NodePort` và sử dụng `Ingress` (public) kết hợp với `ClusterIP` DNS (Private).

### Ingress Endpoints (Truy cập từ trình duyệt Web)

Cần thiết lập file `hosts` (`/etc/hosts` trên Linux/Mac hoặc `C:\Windows\System32\drivers\etc\hosts`) trỏ về IP của máy chủ chạy K3s:

| Service | Domain (gõ vào trình duyệt) | Username | Password |
| --- | --- | --- | --- |
| MinIO Console | `http://minio.local` | minioadmin | nammoadidaphat |
| MinIO S3 API | `http://minio-api.local` | - | - |
| MLflow UI | `http://mlflow.local` | - | - |

### CI/CD Runner Environment Variables (Nội bộ Cluster)

Runner của bạn chạy qua thư viện ARC nằm **BÊN TRONG** K3s cluster, do đó, phần code ML/AI khai báo cực kì an toàn bằng cách chọc thẳng vào luồng nội bộ (internal DNS):

```yaml
env:
  # Goi thang den MLflow tracking server thong qua ClusterIP 5000
  MLFLOW_TRACKING_URI: "http://mlflow-local.mlops-infra.svc.cluster.local:5000"
  
  # Goi thang den MinIO API thong qua ClusterIP 9000
  MLFLOW_S3_ENDPOINT_URL: "http://minio-svc.mlops-infra.svc.cluster.local:9000"
  
  # Chung chi MinIO S3
  AWS_ACCESS_KEY_ID: minioadmin
  AWS_SECRET_ACCESS_KEY: nammoadidaphat
```

*(Kubeflow Pipelines UI nếu setup xong mặc định port-forward ra `8080` trên máy local)*

---

## 7. Quản lý Kubernetes Secrets (GitOps Standard)

Mật khẩu không được lưu dưới dạng Plain-text trong Git. Bạn **bắt buộc** phải tạo 3 Secret này bằng tay trên máy chủ K3s trước khi triển khai các ứng dụng bằng ArgoCD:

```bash
# 1. Secret cho PostgreSQL
kubectl create secret generic postgres-credentials \
  -n mlops-infra \
  --from-literal=postgres-password="nammoadidaphat" \
  --from-literal=password="nammoadidaphat"

# 2. Secret cho MinIO
kubectl create secret generic minio-credentials \
  -n mlops-infra \
  --from-literal=rootUser="minioadmin" \
  --from-literal=rootPassword="nammoadidaphat"

# 3. Secret cho MLflow
kubectl create secret generic mlflow-credentials \
  -n mlops-infra \
  --from-literal=MLFLOW_BACKEND_STORE_URI="postgresql://mlflow:nammoadidaphat@postgres-svc:5432/mlflow" \
  --from-literal=AWS_ACCESS_KEY_ID="minioadmin" \
  --from-literal=AWS_SECRET_ACCESS_KEY="nammoadidaphat" \
  --from-literal=MLFLOW_S3_ENDPOINT_URL="http://minio-svc:9000"
```

---

## 8. Lệnh Troubleshooting Cơ Bản

### Lỗi hiển thị ArgoCD OutOfSync

```bash
# Kiem tra version hoac xem thong bao loi tu ArgoCD
kubectl -n argocd get app <app-name> -o yaml | grep -A5 status
```

### Lỗi Ổ cứng/Thẻ nhớ (PVC) bị treo Pending

```bash
# PVC Pending thong thuong la do K3s local path bi full
kubectl -n mlops-infra describe pvc
kubectl -n kube-system get pods -l app=local-path-provisioner
```

### Lỗi sập Database (Xem Logs)

```bash
# Check raw realtime logs
kubectl logs -n mlops-infra -l app.kubernetes.io/name=postgresql -f
```

---

## 9. Đồng bộ Trọng số Model lên AWS Cloud

Hệ thống hỗ trợ đồng bộ model weights từ MinIO local lên AWS S3, cho phép deploy model trên EKS.

### Kiến trúc

```
[KFP Training] → [MinIO: mlflow-artifacts/] 
                       ↓ (GitHub Actions: model-sync.yml)
                  [AWS S3: mlops-stock-models/mlflow-artifacts/]
                       ↓
                  [EKS Pods dùng model_loader.py + IRSA đọc S3]
```

### Bước 1: Tạo S3 Bucket

```bash
aws s3 mb s3://mlops-stock-models --region ap-southeast-1
```

### Bước 2: Tạo IAM Role cho GitHub Actions (OIDC)

Workflow `model-sync.yml` dùng OIDC — **không cần lưu AWS key trong GitHub Secrets**.

**2a. Tạo OIDC Identity Provider trên AWS:**

```bash
# Lấy thumbprint của GitHub OIDC
THUMBPRINT=$(openssl s_client -connect token.actions.githubusercontent.com:443 -showcerts 2>/dev/null \
  | openssl x509 -fingerprint -noout | cut -d= -f2 | tr -d :)

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list "$THUMBPRINT" \
  --client-id-list "sts.amazonaws.com"
```

**2b. Tạo IAM Role với Trust Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:Quackusarle/MLOps-Stock:*"
        }
      }
    }
  ]
}
```

```bash
# Tạo role
aws iam create-role \
  --role-name GitHubActions-MLOps-S3-Sync \
  --assume-role-policy-document file://trust-policy.json

# Gán policy S3 write
aws iam put-role-policy \
  --role-name GitHubActions-MLOps-S3-Sync \
  --policy-name S3SyncPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
        "Resource": [
          "arn:aws:s3:::mlops-stock-models",
          "arn:aws:s3:::mlops-stock-models/*"
        ]
      }
    ]
  }'
```

**2c. Thêm GitHub Secret:**

```
AWS_OIDC_ROLE_ARN = arn:aws:iam::111122223333:role/GitHubActions-MLOps-S3-Sync
```

### Bước 3: Tạo IAM Role cho EKS Pods (IRSA)

Khi deploy lên EKS, model containers (`tft-api`, `lgbm-api`, `ensemble-api`) cần đọc S3 qua IRSA.

```bash
# Tạo IAM Role cho EKS ServiceAccount
eksctl create iamserviceaccount \
  --name mlops-stock-sa \
  --namespace mlops-stock \
  --cluster YOUR_EKS_CLUSTER_NAME \
  --role-name MLOps-Stock-S3-Access-Role \
  --attach-policy-arn arn:aws:iam::111122223333:policy/S3ReadOnlyMLOpsModels \
  --approve

# Policy cần tạo trước:
aws iam create-policy \
  --policy-name S3ReadOnlyMLOpsModels \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:ListBucket"],
        "Resource": [
          "arn:aws:s3:::mlops-stock-models",
          "arn:aws:s3:::mlops-stock-models/*"
        ]
      }
    ]
  }'
```

### Bước 4: Chuyển từ Local → EKS

Khi deploy lên EKS, cập nhật `values.yaml` của Helm chart:

```yaml
# Thay đổi MLflow config trỏ đến cloud MLflow (nếu có)
mlflow:
  trackingUri: "https://mlflow.your-domain.com"
  s3EndpointUrl: ""   # Để trống → dùng S3 thật thay vì MinIO

# Cập nhật IAM Role ARN
aws:
  serviceAccountRoleArn: "arn:aws:iam::111122223333:role/MLOps-Stock-S3-Access-Role"
```
