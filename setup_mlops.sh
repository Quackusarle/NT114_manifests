#!/bin/bash
set -e

echo "1. Đang tạo Namespace 'mlops-infra'..."
kubectl create namespace mlops-infra || echo "Namespace đã tồn tại, bỏ qua."

echo "2. Đang nạp Secrets cho Postgres và MLflow..."
kubectl create secret generic postgres-credentials \
  --namespace mlops-infra \
  --from-literal=postgres-password="SuperSecretPassword123" || echo "Secret postgres-credentials đã tồn tại."

kubectl create secret generic mlflow-credentials \
  --namespace mlops-infra \
  --from-literal=MLFLOW_BACKEND_STORE_URI="postgresql://mlflow:SuperSecretPassword123@postgres-svc.mlops-infra.svc.cluster.local:5432/mlflow" || echo "Secret mlflow-credentials đã tồn tại."

echo "3. Đang ra lệnh cho ArgoCD triển khai ứng dụng..."
# Dùng namespace argocd để chứa các Application
kubectl apply -n argocd -f ./argocd/infra/postgres.yaml
kubectl apply -n argocd -f ./argocd/infra/mlflow.yaml
kubectl apply -n argocd -f ./argocd/apps/mlops-stock-dev-app.yaml
kubectl apply -n argocd -f ./argocd/apps/mlops-stock-prod-app.yaml

echo "========================================="
echo "Hoàn tất! Hệ thống đang được ArgoCD triển khai."
echo "Bạn có thể gõ lệnh: kubectl get pods -n mlops-infra -w"
echo "để theo dõi quá trình các container khởi động."
