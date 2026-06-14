#!/bin/bash

echo "========================================================================="
echo "🧹 BẮT ĐẦU DỌN DẸP KUBERNETES RESOURCES TRƯỚC KHI TERRAFORM DESTROY 🧹"
echo "========================================================================="
echo "Lý do: Nếu không dọn dẹp các tài nguyên do Kubernetes tự động tạo ra"
echo "(như Load Balancers, EBS Volumes), Terraform sẽ bị kẹt khi xóa VPC!"
echo ""

# 1. Xóa ArgoCD Applications (Để ArgoCD tự động xóa các tài nguyên bên trong)
echo "1. Đang ra lệnh cho ArgoCD gỡ bỏ toàn bộ Ứng dụng (để tránh kẹt Finalizer)..."
kubectl delete application --all -n argocd --timeout=60s || echo "Đã xóa xong hoặc Timeout, tiếp tục..."

# 2. Xóa sạch các Service có type là LoadBalancer
echo "2. Đang xóa các Load Balancer Services (để AWS dọn dẹp ELB)..."
# Lấy danh sách tất cả các Service kiểu LoadBalancer và xóa chúng
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  lb_svcs=$(kubectl get svc -n $ns -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}')
  for svc in $lb_svcs; do
    echo "  -> Đang xóa LoadBalancer: $svc trong namespace $ns"
    kubectl delete svc $svc -n $ns
  done
done

# 3. Xóa Ingresses (nếu có, để ALB Controller dọn dẹp ALB)
echo "3. Đang xóa các Ingresses (nếu có)..."
kubectl delete ingress --all --all-namespaces || true

# 4. Xóa các PVC để gỡ ổ cứng EBS
echo "4. Đang xóa các Persistent Volume Claims (PVC) để nhả ổ cứng AWS EBS..."
kubectl delete pvc --all -n mlops-infra || true

# Đợi 1 chút cho AWS Load Balancer Controller và EBS CSI kịp gọi API lên AWS để xóa tài nguyên vật lý
echo "5. Đang chờ 15 giây để AWS dọn dẹp tài nguyên vật lý..."
sleep 15

# 5. Xóa namespace
echo "6. Đang xóa Namespace 'mlops-infra'..."
kubectl delete namespace mlops-infra --timeout=30s --wait=false || true

echo "========================================================================="
echo "✅ DỌN DẸP HOÀN TẤT!"
echo "Bây giờ bạn có thể an tâm chuyển sang thư mục Terraform và chạy:"
echo "   terraform destroy"
echo "========================================================================="
