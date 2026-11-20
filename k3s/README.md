# BackHaulBid — Triển khai K3s trên AWS EC2

Bộ manifest Kubernetes chuẩn Kustomize trong thư mục này triển khai toàn bộ hệ thống BackHaulBid (4 stateful services + 10 application services + Traefik Ingress) lên một máy **AWS EC2 cài K3s**.

## 1. Cấu trúc thư mục

| File / Thư mục | Vai trò |
|---|---|
| `.env.k3s.example` | Mẫu biến môi trường đầy đủ (copy thành `.env.k3s` trước khi chạy) |
| `00-namespace.yaml` | Namespace `backhaulbid` |
| `01-configmap.yaml` | Cấu hình không nhạy cảm mặc định (`deploy.sh` sẽ đồng bộ từ `.env.k3s`) |
| `02-postgres.yaml` – `05-rabbitmq.yaml` | `StatefulSet` + `PVC (local-path)` cho PostgreSQL (kèm script tạo 4 DB), MongoDB, Redis, RabbitMQ |
| `06-eureka-server.yaml` | Service discovery Eureka |
| `07-core-services.yaml` | 5 Spring Boot services: `identity`, `fleet`, `wallet`, `contract`, `media` |
| `08-node-services.yaml` | 2 NestJS services (HTTP + Socket.IO + RabbitMQ): `bidding`, `notification` |
| `09-web-portal.yaml` | Next.js standalone `web-portal` |
| `10-api-gateway.yaml` | Spring Cloud Gateway (cổng vào duy nhất cho API, Socket.IO và Web Portal) |
| `11-ingress.yaml` | Traefik Ingress HTTP mặc định (chạy ngay với IP EC2 hoặc domain) |
| `11-ingress-tls.yaml.example` | Mẫu Ingress HTTPS tự động với `cert-manager` + Let's Encrypt khi có domain |
| `scripts/ec2-bootstrap.sh` | Cài Docker + Swap 4GB + K3s trên EC2 Ubuntu mới |
| `scripts/build-and-import.sh` | Build 10 image và import vào K3s containerd (hoặc `--push` lên Registry) |
| `scripts/deploy.sh` | Validate `.env.k3s`, tạo Secret/ConfigMap và triển khai theo đúng thứ tự |

---

## 2. Khởi tạo AWS EC2 mới

1. **EC2 Instance khuyến nghị**:
   - **AMI**: Ubuntu Server 22.04 LTS hoặc 24.04 LTS (**x86_64 / amd64**)
   - **Instance type**: `t3.large` hoặc `t3a.large` (2 vCPU, **8 GB RAM**)
   - **EBS Storage**: tối thiểu **30 GB `gp3`** (chứa OS, Docker build cache và PVC dữ liệu)
   - **Elastic IP**: gắn 1 Elastic IP cố định để IP không đổi khi stop/start EC2
2. **Security Group (Inbound Rules)**:
   - `22/TCP` (SSH): **chỉ mở cho IP của bạn (My IP)**
   - `80/TCP` (HTTP): `0.0.0.0/0`
   - `443/TCP` (HTTPS): `0.0.0.0/0`
   - **Không mở** các port nội bộ (`5432`, `27017`, `6379`, `5672`, `15672`, `8761`, `8080`, `3000`, `6443`) ra Internet.

---

## 3. Các bước cài đặt & deploy trên EC2

### Bước 1: Clone các repository ngang hàng

```bash
mkdir -p ~/backhaulbid && cd ~/backhaulbid
git clone https://github.com/Phucvinh0411/backhaulbid-infrastructure.git
git clone https://github.com/Phucvinh0411/backhaulbid-core-services.git
git clone https://github.com/Phucvinh0411/backhaulbid-node-services.git
git clone https://github.com/Phucvinh0411/backhaulbid-web-portal.git
```

### Bước 2: Cài đặt Docker + K3s

```bash
cd ~/backhaulbid/backhaulbid-infrastructure
chmod +x k3s/scripts/*.sh
./k3s/scripts/ec2-bootstrap.sh
newgrp docker
```

### Bước 3: Tạo và điền file `.env.k3s`

```bash
cp k3s/.env.k3s.example k3s/.env.k3s
chmod 600 k3s/.env.k3s
nano k3s/.env.k3s
```

Gợi ý lệnh sinh secret ngẫu nhiên ngay trên EC2:

```bash
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
echo "MONGO_PASSWORD=$(openssl rand -hex 24)"
echo "REDIS_PASSWORD=$(openssl rand -hex 24)"
echo "RABBITMQ_PASSWORD=$(openssl rand -hex 24)"
echo "JWT_SECRET=$(openssl rand -base64 48)"
echo "INTERNAL_SERVICE_TOKEN=$(openssl rand -hex 32)"
echo "INTERNAL_WALLET_TOKEN=$(openssl rand -hex 32)"
echo "DRIVER_REPLAY_KEY=$(openssl rand -base64 32)"
echo "EKYC_EVIDENCE_ENCRYPTION_KEY=$(openssl rand -base64 32)"
```

### Bước 4: Build & nạp 10 image vào K3s

```bash
./k3s/scripts/build-and-import.sh
```

*(Khi sửa code về sau, bạn chỉ cần build lại đúng service đã đổi, ví dụ: `./k3s/scripts/build-and-import.sh web-portal api-gateway` rồi chạy `kubectl -n backhaulbid rollout restart deploy/web-portal deploy/api-gateway`.)*

### Bước 5: Triển khai toàn bộ stack

```bash
./k3s/scripts/deploy.sh
```

---

## 4. Bật HTTPS miễn phí khi có Domain (Let's Encrypt)

1. Trỏ bản ghi DNS `A` của domain (ví dụ `backhaulbid.yourdomain.com`) về **Elastic IP** của EC2.
2. Cài `cert-manager`:
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
   kubectl -n cert-manager rollout status deploy/cert-manager-webhook
   ```
3. Tạo file `k3s/11-ingress-tls.yaml` từ mẫu `k3s/11-ingress-tls.yaml.example`, thay `YOUR_EMAIL` và `YOUR_DOMAIN`.
4. Cập nhật `k3s/.env.k3s`:
   - `PUBLIC_BASE_URL=https://YOUR_DOMAIN`
   - `INGRESS_HOST=YOUR_DOMAIN`
   - `COOKIE_SECURE=true`
5. Build lại `web-portal` (vì `NEXT_PUBLIC_GATEWAY_URL` được nhúng lúc build) và deploy lại:
   ```bash
   ./k3s/scripts/build-and-import.sh web-portal
   ./k3s/scripts/deploy.sh
   ```

---

## 5. Kết nối Mobile App (`backhaulbid-driver-app`)

Đặt `EXPO_PUBLIC_API_BASE_URL` trong `.env` của `backhaulbid-driver-app` trùng với `PUBLIC_BASE_URL` (ví dụ `http://<EC2_PUBLIC_IP>` hoặc `https://YOUR_DOMAIN`).

---

## 6. Vận hành & Gỡ lỗi nhanh

```bash
# Xem toàn bộ Pod và dung lượng RAM/CPU thực tế
kubectl -n backhaulbid get pods -o wide
kubectl -n backhaulbid top pods

# Xem log một service
kubectl -n backhaulbid logs -f deploy/api-gateway
kubectl -n backhaulbid logs -f deploy/identity-service

# Truy cập Eureka (8761) hoặc RabbitMQ UI (15672) an toàn từ máy cá nhân qua SSH tunnel
ssh -i <key.pem> -L 8761:127.0.0.1:8761 -L 15672:127.0.0.1:15672 ubuntu@<EC2_PUBLIC_IP>
# Sau đó trên EC2 chạy:
kubectl -n backhaulbid port-forward svc/eureka-server 8761:8761
kubectl -n backhaulbid port-forward svc/rabbitmq 15672:15672
```
