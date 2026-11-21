# BackHaulBid — Triển khai K3s chuẩn Kubernetes (App-Only + Managed DBs)

Bộ manifest chuẩn **Kustomize** (`base/` + `overlays/`) triển khai tầng ứng dụng stateless của BackHaulBid (**9 Application Deployments × mặc định 2 replicas = 18 Pods + Traefik Ingress**) lên **K3s**, tách toàn bộ cơ sở dữ liệu và message broker ra dịch vụ ngoài:

- **PostgreSQL** (`4 DB`: `backhaulbid_identity`, `backhaulbid_fleet`, `backhaulbid_wallet`, `backhaulbid_contract`) → **Aiven for PostgreSQL** (`?sslmode=require`)
- **Redis / Valkey** (`api-gateway` rate-limit + `bidding-service` cache/lock) → **Aiven for Valkey** (`rediss://` TLS)
- **MongoDB** (`backhaulbid_bidding`, `backhaulbid_notification`) → **MongoDB Atlas** (`mongodb+srv://`, *vì Aiven không hỗ trợ MongoDB*)
- **RabbitMQ** (`contract-service`, `bidding-service`, `notification-service`) → **CloudAMQP / Amazon MQ** (`amqps://`, *vì Aiven không hỗ trợ RabbitMQ*)
- **Không chạy `eureka-server` trên K3s**: định tuyến nội bộ trực tiếp qua Kubernetes `ClusterIP` Service DNS (`EUREKA_ENABLED=false`). *(Local `docker compose` vẫn giữ nguyên `EUREKA_ENABLED=true` với `lb://`.)*
- **Traefik Ingress tách luồng tại edge**: `/api/v1`, `/bidding-socket`, `/notification-socket`, `/v3/api-docs`, `/swagger-ui`, `/swagger-ui.html`, `/webjars` → `api-gateway:8080`; `/` (`/_next/**`, `/api/auth/**`, `/api/bidding/**`) → `web-portal:3000`.
- **Sẵn sàng chạy `replicas: 2` (High Availability)**:
  - Socket.IO trên `bidding-service` và `notification-service` dùng `@socket.io/redis-adapter` (qua Aiven Valkey) + `sessionAffinity: ClientIP` + Traefik sticky cookie trên `api-gateway`.
  - Khóa đặt giá (`BidService`) và tác vụ định kỳ (`AuctionService`, `AuctionAwardService`, `BiddingSagaService`) dùng Redis distributed lock; tác vụ `@Scheduled` (`identity`, `contract`) dùng PostgreSQL advisory lock (`pg_try_advisory_lock`).
  - SSE khiếu nại (`ComplaintService`) đồng bộ giữa các Pod qua RabbitMQ `FanoutExchange` (`contract.complaint.sse.fanout`).
  - Tham số hóa pool Postgres theo nhóm dịch vụ (`DB_POOL_MAX_SIZE=2` cho `identity`/`contract` có advisory lock, `DB_POOL_LIGHT_MAX_SIZE=1` cho `fleet`/`wallet`, `DB_POOL_MIN_IDLE=1`): tổng tối đa `(2×2 + 2×1) × 2 = 12` kết nối, nằm gọn dưới ngưỡng **`15` connections** của Aiven PostgreSQL Free (dư slot cho rolling update).
- **Bảo mật Pod chuẩn K8s *Restricted***: tất cả 9 Deployment chạy non-root (`runAsNonRoot: true`, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`), `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `readOnlyRootFilesystem: true` (kèm `emptyDir` cho `/tmp` và `.next/cache`), có `NetworkPolicy` cách ly nội bộ (`05-network-policies.yaml`) và tự động rolling update khi ConfigMap/Secret đổi (`backhaulbid.vn/config-checksum`).

---

## 1. Cấu trúc thư mục

| File / Thư mục | Vai trò |
|---|---|
| `.env.k3s.example` | Mẫu biến môi trường (Docker Hub, Aiven PostgreSQL, Aiven Valkey, MongoDB Atlas, CloudAMQP, S3, JWT...) |
| `base/` | Manifest gốc stateless: `00-namespace.yaml`, `01-core-services.yaml`, `02-node-services.yaml`, `03-web-portal.yaml`, `04-api-gateway.yaml`, `05-network-policies.yaml` |
| `overlays/http/` | Kustomize overlay mặc định (Traefik HTTP qua IP EC2 hoặc domain) |
| `overlays/tls/` | Mẫu Kustomize overlay HTTPS tự động (`cert-manager` + Let's Encrypt) |
| `scripts/ec2-bootstrap.sh` | Cài Docker + Swap 4GB + K3s trên EC2 Ubuntu mới |
| `scripts/build-and-import.sh` | Build 9 image trên Linux/EC2 để import vào K3s containerd hoặc `--push` lên Docker Hub |
| `scripts/build-and-push-dockerhub.ps1` | Script PowerShell cho Windows để build (`linux/amd64`) & push image lên Docker Hub |
| `scripts/deploy.sh` | Validate `.env.k3s`, tách URI, tạo Secrets (`backhaulbid-secrets`, `dockerhub-regcred`), ConfigMap và `kubectl apply -k` |

---

## 2. Khởi tạo AWS EC2 & Tài nguyên ngoài

### A. AWS EC2 cho K3s (chỉ chạy App stateless)
Vì đã tách toàn bộ 4 DB/broker ra ngoài và chạy mặc định **`replicas: 2`** (18 Pods), tổng tài nguyên yêu cầu là **`900m` CPU requests, `3456 MiB` RAM requests / `7808 MiB` RAM limits** (chưa tính RAM hệ thống K3s/Traefik và `maxSurge: 1` khi rolling update):
- **AMI**: Ubuntu Server 22.04 LTS hoặc 24.04 LTS (`x86_64 / amd64`)
- **Instance type**:
  - **`t3.xlarge` (4 vCPU, 16 GB RAM)** *(khuyên dùng cho `APP_REPLICAS=2`)*: chạy dư dả cả 18 Pod lẫn rolling update không chạm swap.
  - **`t3.large` / `t3a.large` (2 vCPU, 8 GB RAM)**: phù hợp khi đặt **`APP_REPLICAS=1`** trong `.env.k3s` (chỉ 9 Pods: `450m` CPU requests, `1728 MiB` RAM requests / `3904 MiB` RAM limits).
- **EBS Storage**: tối thiểu **25–30 GB `gp3`** (khi pull image từ Docker Hub) hoặc **40–50 GB** (nếu build Docker trực tiếp trên EC2).
- **Security Group**: mở `22/TCP` (chỉ My IP), `80/TCP`, `443/TCP`; không mở `8080`, `3000`, `6443` ra Internet.

### B. Chuẩn bị 4 CSDL ngoài trước khi deploy
1. **Aiven for PostgreSQL**:
   - Tạo 1 service PostgreSQL trên Aiven (chọn cùng region AWS như `ap-southeast-1` nếu có để giảm độ trễ).
   - Tạo đủ **4 database** trên service đó: `backhaulbid_identity`, `backhaulbid_fleet`, `backhaulbid_wallet`, `backhaulbid_contract` (Flyway sẽ tự tạo bảng khi từng service khởi động).
   - Lấy `Host`, `Port`, `User` (`avnadmin`), `Password` điền vào `.env.k3s` (`POSTGRES_SSLMODE=require`).
2. **Aiven for Valkey**:
   - Tạo 1 service Valkey, copy `Service URI` dạng `rediss://default:<pass>@<host>:<port>` dán vào `REDIS_URL`.
3. **MongoDB Atlas**:
   - Tạo Cluster (Free `M0` hoặc Dedicated), cấu hình Network Access (IP của EC2) và DB User, rồi điền `MONGO_BIDDING_URI` (`/backhaulbid_bidding`) và `MONGO_NOTIFICATION_URI` (`/backhaulbid_notification`).
4. **CloudAMQP / Amazon MQ**:
   - Tạo instance RabbitMQ (CloudAMQP có gói *Little Lemur* free), copy AMQP URI dạng `amqps://<user>:<pass>@<host>/<vhost>` dán vào `RABBITMQ_URL`.

---

## 3. Chuẩn bị & nạp Container Image qua Docker Hub

1. Trên **máy Windows** (các repo đặt ngang hàng nhau), copy `k3s/.env.k3s.example` → `k3s/.env.k3s` và điền `PUBLIC_BASE_URL`, `IMAGE_REGISTRY=<dockerhub_user>`, `IMAGE_PREFIX=backhaulbid-`, `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`:
   ```powershell
   .\k3s\scripts\build-and-push-dockerhub.ps1 -Tag v1.0.0
   # Hoặc build lại riêng 1-2 service:
   .\k3s\scripts\build-and-push-dockerhub.ps1 -Services api-gateway,bidding-service -Tag v1.0.1
   ```
2. *(Trên Linux/macOS)* dùng:
   ```bash
   ./k3s/scripts/build-and-import.sh --push --tag v1.0.0
   ```
3. *(Hoặc không dùng Docker Hub)* giữ `IMAGE_REGISTRY=backhaulbid`, `IMAGE_PREFIX=` trên EC2 rồi chạy `./k3s/scripts/build-and-import.sh`.

---

## 4. Cài đặt K3s & Deploy trên EC2

```bash
# 1. Cài Docker + Swap 4GB + K3s
cd ~/backhaulbid/backhaulbid-infrastructure
chmod +x k3s/scripts/*.sh
./k3s/scripts/ec2-bootstrap.sh
newgrp docker

# 2. Tạo file cấu hình .env.k3s và điền đầy đủ secret + URL của Aiven / Atlas / CloudAMQP
cp k3s/.env.k3s.example k3s/.env.k3s
chmod 600 k3s/.env.k3s
nano k3s/.env.k3s

# 3. Deploy stack lên K3s
./k3s/scripts/deploy.sh --tag v1.0.0
```

Gợi ý tạo nhanh các secret ứng dụng trên EC2:
```bash
echo "JWT_SECRET=$(openssl rand -base64 48)"
echo "INTERNAL_SERVICE_TOKEN=$(openssl rand -hex 32)"
echo "INTERNAL_WALLET_TOKEN=$(openssl rand -hex 32)"
echo "DRIVER_REPLAY_KEY=$(openssl rand -base64 32)"
echo "EKYC_EVIDENCE_ENCRYPTION_KEY=$(openssl rand -base64 32)"
```

---

## 5. Bật HTTPS miễn phí khi có Domain (Let's Encrypt)

1. Trỏ DNS `A` của domain về Elastic IP của EC2.
2. Cài `cert-manager`:
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
   kubectl -n cert-manager rollout status deploy/cert-manager-webhook
   ```
3. Kích hoạt overlay TLS (đã có sẵn trong `.gitignore`):
   ```bash
   cp k3s/overlays/tls/kustomization.yaml.example k3s/overlays/tls/kustomization.yaml
   cp k3s/overlays/tls/ingress-tls.yaml.example k3s/overlays/tls/ingress-tls.yaml
   nano k3s/overlays/tls/ingress-tls.yaml   # Thay YOUR_EMAIL và YOUR_DOMAIN
   ```
4. Cập nhật `PUBLIC_BASE_URL=https://YOUR_DOMAIN`, `INGRESS_HOST=YOUR_DOMAIN`, `COOKIE_SECURE=true` trong `k3s/.env.k3s`, build & push lại `web-portal`, rồi chạy `./k3s/scripts/deploy.sh`.

---

## 6. Kết nối Mobile App & Gỡ lỗi nhanh

- Đặt `EXPO_PUBLIC_API_BASE_URL` trong `.env` của `backhaulbid-driver-app` trùng với `PUBLIC_BASE_URL`.
- Kiểm tra nhanh cụm K3s:
  ```bash
  kubectl kustomize k3s/overlays/http
  kubectl -n backhaulbid get pods -o wide
  kubectl -n backhaulbid top pods
  kubectl -n backhaulbid logs -f deploy/api-gateway
  kubectl -n backhaulbid logs -f deploy/bidding-service
  kubectl -n backhaulbid logs -f deploy/contract-service
  ```

---

## 7. GitHub Actions CI/CD

### A. Continuous Integration (`push` trên `main`/`develop`, `pull_request` vào `main`/`develop`/`deploy`)
- **`backhaulbid-infrastructure`** (`.github/workflows/ci-infra.yml`):
  - Chạy test Java 21 cho `api-gateway` (`./mvnw clean test`).
  - Kiểm tra cú pháp + định dạng dòng LF cho `k3s/scripts/*.sh`, kiểm tra `docker compose --env-file .env.example config --quiet`, và render `kubectl kustomize` cho `k3s/base`, `k3s/overlays/http`, `k3s/overlays/tls` (từ file `.example`).
- **`backhaulbid-core-services`** (`.github/workflows/ci-spring.yml`): chạy `mvn clean test -B --no-transfer-progress` với JDK 21.
- **`backhaulbid-node-services`** (`.github/workflows/ci-node.yml`): chạy `npm ci --legacy-peer-deps`, `npm run lint --if-present`, `npm test --if-present`, `npm run build` (`bidding` & `notification`) trên Node `20.x` và `22.x`.
- **`backhaulbid-web-portal`** (`.github/workflows/ci-web.yml`): chạy `npm ci`, `npm run lint`, `npm test`, `npm run build` (Next.js) trên Node `20.x`.

### B. Continuous Deployment tự động theo nhánh `deploy` (`cd-k3s-dockerhub.yml` + `cd-dispatch.yml`)
- **Đẩy/merge code vào nhánh `deploy` ở bất kỳ repo nào trong 4 repo:**
  - `backhaulbid-core-services`, `backhaulbid-node-services`, `backhaulbid-web-portal` có `.github/workflows/cd-dispatch.yml`: phát hiện đúng service bị sửa (`git diff`) và gửi `repository_dispatch` (`deploy-services`) kèm short SHA sang `backhaulbid-infrastructure`.
  - `backhaulbid-infrastructure` có `.github/workflows/cd-k3s-dockerhub.yml`:
    - Khi nhận `repository_dispatch` từ app repo: chỉ build & push đúng image bị sửa từ nhánh `deploy`, rồi SSH chạy `./k3s/scripts/deploy.sh --tag <sha> --services <svc>`.
    - Khi có `push` trực tiếp vào nhánh `deploy` của `infra`: nếu sửa `api-gateway/` thì build `api-gateway`; nếu chỉ sửa `k3s/` thì chạy `./k3s/scripts/deploy.sh --services none` để cập nhật manifest/ConfigMap/Secret mà giữ nguyên tag các Pod đang chạy.
    - Vẫn hỗ trợ chạy tay qua **Actions → CD - Build & Deploy K3s (Docker Hub) → Run workflow** (`services: all | none | svc1,svc2`, `source_branch: deploy | main | develop`, `image_tag`, `deploy_to_ec2`).
- **Quy trình deploy lần đầu tiên trên EC2 K3s mới:**
  1. Cài đủ Secrets bên dưới trên GitHub rồi push nhánh `deploy` của cả 4 repo.
  2. Chạy tay **`workflow_dispatch`** trong `backhaulbid-infrastructure` với `services: all`, `source_branch: deploy` **1 lần đầu** để tạo đủ 9 Deployment trong cluster.
  3. Từ các lần sau, chỉ cần merge/push vào nhánh `deploy` của repo nào là service đó tự cập nhật lên EC2.

#### Cấu hình GitHub Secrets & Variables
1. **Trong 3 repo app (`backhaulbid-core-services`, `backhaulbid-node-services`, `backhaulbid-web-portal`):**
   - Secret `INFRA_DISPATCH_TOKEN`: GitHub Fine-grained PAT cấp quyền **Contents: Read and write** giới hạn riêng cho repository `Phucvinh0411/backhaulbid-infrastructure`.
2. **Trong repo `Phucvinh0411/backhaulbid-infrastructure` (*Repository Secrets*):**
   - `DOCKERHUB_USERNAME`: tên tài khoản Docker Hub.
   - `DOCKERHUB_TOKEN`: Docker Hub Access Token (quyền *Read & Write*).
   - `PUBLIC_BASE_URL`: URL truy cập hệ thống (vd: `http://<EC2_PUBLIC_IP>` hoặc `https://domain.com`) — bắt buộc khi build `web-portal` *(có thể đặt ở Variables thay cho Secrets)*.
   - `EC2_HOST`: IP Public hoặc domain SSH tới EC2 (bắt buộc khi deploy lên EC2).
   - `EC2_SSH_KEY`: toàn bộ nội dung private key `.pem` dùng SSH vào EC2.
   - `EC2_USER` *(tùy chọn)*: user SSH trên EC2 (mặc định `ubuntu`).
3. **Trong repo `Phucvinh0411/backhaulbid-infrastructure` (*Repository Variables* — tùy chọn):**
   - `IMAGE_REGISTRY`: namespace/org Docker Hub nếu khác `DOCKERHUB_USERNAME`.
   - `IMAGE_PREFIX`: tiền tố tên image (mặc định `backhaulbid-`; đặt `none` nếu không dùng prefix).
   - `NEXT_PUBLIC_GOOGLE_CLIENT_ID`: Google OAuth Web Client ID nhúng lúc build `web-portal`.
   - `EC2_SSH_PORT`: cổng SSH (mặc định `22`).
   - `EC2_PROJECT_DIR`: đường dẫn thư mục `backhaulbid-infrastructure` trên EC2 (mặc định `~/backhaulbid/backhaulbid-infrastructure`).
