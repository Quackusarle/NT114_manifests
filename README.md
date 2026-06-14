# MLOps-Stock Manifests (GitOps Repository)

Kho lưu trữ này đóng vai trò là Nguồn Chân lý (Source of Truth) cho toàn bộ cấu hình hạ tầng và trạng thái triển khai của hệ thống MLOps-Stock, tuân thủ nghiêm ngặt mô hình **GitOps**.

## Kiến trúc Triển khai (Continuous Deployment)

Toàn bộ hệ thống được triển khai trên môi trường **Kubernetes** thông qua **ArgoCD**. Quá trình vận hành được thiết kế như sau:

- **Configuration Management**: Quản lý cấu hình hạ tầng dưới dạng mã (Infrastructure as Code) sử dụng **Helm Charts**.
- **ArgoCD Synchronization**: ArgoCD hoạt động dưới dạng Kubernetes Controller, liên tục giám sát (watch) kho lưu trữ này. Mọi thay đổi trong file `values.yaml` (ví dụ: cập nhật Image Tag từ luồng CI) sẽ được ArgoCD tự động áp dụng (sync) vào cụm Kubernetes theo thời gian thực mà không cần can thiệp thủ công.
- **Traffic Routing**: Sử dụng **AWS ALB Ingress Controller** để định tuyến luồng dữ liệu (traffic) từ internet vào các dịch vụ nội bộ bên trong cụm (Dashboard, Ensemble API).
- **MLflow Tracking Server**: Triển khai máy chủ MLflow nội bộ để theo dõi các chu kỳ huấn luyện mô hình. Hệ thống sử dụng PostgreSQL làm Backend Store và Amazon S3 làm Artifact Store, tích hợp cơ chế cấp quyền tự động (IAM Role for Service Accounts - IRSA) của AWS thay vì sử dụng khóa tĩnh.

## Luồng Hoạt động GitOps
1. Nhận bản cập nhật mã băm (Commit SHA) từ kho lưu trữ mã nguồn `MLOps-Stock`.
2. Ghi đè vào các file cấu hình tương ứng (Helm values).
3. ArgoCD phát hiện thay đổi (Out of Sync).
4. ArgoCD tự động kéo các Docker Image mới từ Registry và khởi tạo/cập nhật các Pods trên cụm Kubernetes.

**Contributors:**
- Trần Việt Hoàng
- Lê Đình Hiếu
