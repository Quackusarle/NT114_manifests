#!/bin/bash
echo "Đang cập nhật Kubeconfig cho cụm EKS 'mlops-stock'..."
aws eks update-kubeconfig --region us-east-1 --name mlops-stock
echo "Cập nhật thành công! Kiểm tra các Node:"
kubectl get nodes
