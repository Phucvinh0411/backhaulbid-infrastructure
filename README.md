# BackHaulBid local stack

Docker Compose chạy toàn bộ backend BackHaulBid: data stores, service discovery,
core services, API Gateway và bidding service. Web portal nằm sau profile tùy chọn.

## Yêu cầu

- Docker Desktop với Docker Compose v2.
- Các repository nằm cùng cấu trúc:

```text
KLTN/
├── be/
│   ├── backhaulbid-infrastructure/
│   ├── backhaulbid-core-services/
│   └── backhaulbid-bidding-service/
└── fe/
    └── backhaulbid-web-portal/
```

## Khởi động

Từ thư mục `KLTN/be`:

```bash
docker compose up --build -d
docker compose ps
```

Lệnh mặc định không build hoặc khởi động frontend. Khi thật sự cần chạy cả web:

```bash
docker compose --profile frontend up --build -d
```

Compose chỉ hoàn tất dependency chain khi Eureka, core services và gateway đã
qua healthcheck. Theo dõi log khi cần:

```bash
docker compose logs -f api-gateway identity-service web-portal
```

Dừng stack nhưng giữ dữ liệu:

```bash
docker compose down
```

`docker compose down -v` sẽ xóa toàn bộ dữ liệu PostgreSQL, MongoDB, Redis và
RabbitMQ; chỉ dùng khi chủ động muốn reset môi trường.

## Endpoint local

| Thành phần | URL/port |
| --- | --- |
| Web portal | http://localhost:3000 |
| API Gateway | http://localhost:8080 |
| Identity service | http://localhost:8081 |
| Fleet service | http://localhost:8082 |
| Wallet service | http://localhost:8083 |
| Contract service | http://localhost:8084 |
| Eureka dashboard | http://localhost:8761 |
| Bidding service | http://localhost:3001 |
| PostgreSQL | localhost:5432 |
| MongoDB | localhost:27017 |
| Redis | localhost:6379 |
| RabbitMQ | localhost:5672 |
| RabbitMQ management | http://localhost:15672 |

Browser chỉ gọi API Gateway. Gateway xác thực cookie `accessToken` hoặc Bearer
token rồi tự tạo các header danh tính tin cậy cho downstream services.

## Cấu hình

Toàn bộ cấu hình local của hệ thống được đặt trong **một file duy nhất** là
`be/backhaulbid-infrastructure/.env`, nằm cạnh `docker-compose.yml`. Compose
đọc trực tiếp file này rồi truyền cấu hình cần thiết cho các service; không tạo
hoặc copy thêm `.env` ở frontend để chạy cùng môi trường.

| Biến | Mục đích |
| --- | --- |
| `JWT_SECRET` | Khóa ký JWT dùng chung giữa identity service và gateway |
| `POSTGRES_USER`, `POSTGRES_PASSWORD` | Tài khoản PostgreSQL local |
| `MONGO_USER`, `MONGO_PASSWORD` | Tài khoản MongoDB local |
| `REDIS_PASSWORD` | Mật khẩu Redis local |
| `RABBITMQ_USER`, `RABBITMQ_PASSWORD` | Tài khoản RabbitMQ local |
| `NEXT_PUBLIC_GATEWAY_URL` | Gateway public được web portal sử dụng |
| `NEXT_PUBLIC_BIDDING_SOCKET_PATH` | Đường dẫn websocket bidding |
| `NEXT_PUBLIC_VNPT_EKYC_BACKEND_URL` | Endpoint VNPT eKYC |
| `NEXT_PUBLIC_VNPT_EKYC_TOKEN_KEY` | Token key VNPT eKYC |
| `NEXT_PUBLIC_VNPT_EKYC_TOKEN_ID` | Token ID VNPT eKYC |
| `NEXT_PUBLIC_VNPT_EKYC_AUTH` | Access token VNPT eKYC |

Đây là **nguồn cấu hình duy nhất** cho web portal và là nguồn mặc định của
môi trường Compose. Không tạo hoặc duy trì các biến `NEXT_PUBLIC_*` tương ứng
trong `fe/backhaulbid-web-portal/.env`. Chạy FE độc lập bằng `npm run dev`/
`npm run build`; script sẽ nạp trực tiếp file infrastructure này. Các file
`.env`/`.env.example` còn nằm trong service Node chỉ phục vụ tương thích khi
chạy service riêng lẻ, không được dùng để cấu hình Compose hoặc FE.

Giá trị mặc định trong Compose chỉ dành cho phát triển local. Môi trường thật
phải truyền secret riêng từ secret manager và bật HTTPS; không tái sử dụng các
giá trị mặc định.

## Tài khoản local

`identity-service` tạo các tài khoản dưới đây bằng Flyway dev migration khi chạy
bằng Compose. Migration chỉ thêm tài khoản còn thiếu nên database local đã có dữ
liệu demo sẽ không bị ghi đè.

| Vai trò | Số điện thoại | Mật khẩu mặc định |
| --- | --- | --- |
| Admin | `0900000001` | `Admin@123` |
| Nhà xe | `0900000002` | `Carrier@123` |
| Chủ hàng | `0900000003` | `Shipper@123` |

## Kiến trúc

- Eureka Server quản lý discovery cho bốn core services và API Gateway.
- Gateway định tuyến bằng `lb://`, xác thực JWT và loại bỏ header danh tính do
  client tự gửi.
- Health của gateway chỉ `UP` khi đủ instance cho identity, fleet, wallet và
  contract routes.
- Web portal gọi gateway public qua `localhost:8080`; các Next server routes gọi
  nội bộ qua `http://api-gateway:8080`.

Quyết định về trust boundary được ghi tại
[`docs/decisions/001-gateway-trusted-identity.md`](docs/decisions/001-gateway-trusted-identity.md).
