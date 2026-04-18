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
