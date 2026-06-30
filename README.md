# 🛠️ BackHaulBid Infrastructure

> **Hạ Tầng Ứng Dụng Dùng Chung (Docker Compose, Databases, Event Broker, Cache & PLG Logging Stack)**
>
> BackHaulBid Infrastructure là kho lưu trữ quản lý hạ tầng dùng chung cho toàn bộ nền tảng B2B BackHaulBid. Kho mã nguồn này chứa cấu hình Docker Compose để tự động dựng các cơ sở dữ liệu quan hệ và phi cấu trúc, hàng đợi thông điệp (Message Broker), bộ nhớ đệm (Cache) và giải pháp giám sát, tập hợp log tập trung PLG Stack.

---

## 🛠️ Thành Phần Hạ Tầng (Middleware Stack)

Khi kích hoạt Docker Compose, các thành phần sau sẽ được triển khai và cấu hình liên thông:

*   **Database quan hệ**: ![PostgreSQL](https://img.shields.io/badge/PostgreSQL_16-4169E1?style=flat-square&logo=postgresql&logoColor=white) (Lưu trữ dữ liệu nghiệp vụ chính của core services).
*   **Database tài liệu**: ![MongoDB](https://img.shields.io/badge/MongoDB_7.0-47A248?style=flat-square&logo=mongodb&logoColor=white) (Lưu trữ lịch sử và phiên đấu giá thời gian thực).
*   **Event Broker**: ![RabbitMQ](https://img.shields.io/badge/RabbitMQ_3.13-FF6600?style=flat-square&logo=rabbitmq&logoColor=white) (Đảm nhận truyền tin nhắn bất đối xứng giữa các dịch vụ).
*   **Cache & Lock**: ![Redis](https://img.shields.io/badge/Redis_7-DC382D?style=flat-square&logo=redis&logoColor=white) (Lưu trữ tạm thời trạng thái phòng đấu giá và khóa phân tán).
*   **Logging Stack (PLG)**:
    *   **Promtail**: Thu gom log từ console của các Docker containers.
    *   **Loki**: Nhận log từ Promtail, lập chỉ mục và lưu trữ.
    *   **Grafana**: Giao diện hiển thị biểu đồ đo đạc (Metrics) và truy vấn logs.

---

## 📌 Yêu Cầu Môi Trường (Prerequisites)

*   [Docker Desktop](https://www.docker.com/products/docker-desktop/) (hỗ trợ cả Windows, macOS, Linux).
*   Công cụ CLI `docker` và `docker-compose` (hoặc cú pháp mới `docker compose`).
*   Ít nhất 4GB RAM trống trên Docker VM để vận hành toàn bộ stack hạ tầng mượt mà.

---

## 🚀 Kích Hoạt Hạ Tầng (Getting Started)

1.  **Clone repository và di chuyển vào thư mục:**
    ```bash
    git clone https://github.com/backhaulbid/backhaulbid-infrastructure.git
    cd backhaulbid-infrastructure
    ```

2.  **Khởi động toàn bộ môi trường hạ tầng (chạy ngầm):**
    ```bash
    docker compose up -d
    # hoặc sử dụng cú pháp cũ:
    docker-compose up -d
    ```
    *Lệnh này sẽ tải các Docker images cần thiết, tạo mạng nội bộ `backhaulbid-network` và khởi chạy tất cả các dịch vụ.*

3.  **Kiểm tra trạng thái các container:**
    ```bash
    docker compose ps
    ```

4.  **Tắt và dọn dẹp môi trường hạ tầng:**
    ```bash
    docker compose down
    # Nếu muốn xóa sạch toàn bộ ổ đĩa dữ liệu (Volumes):
    docker compose down -v
    ```

---

## 📂 Cơ Cấu Thư Mục (Project Structure)

```text
backhaulbid-infrastructure/
├── grafana/
│   └── provisioning/
│       └── datasources/
│           └── datasource.yml # Tự động thiết lập Loki làm nguồn dữ liệu trong Grafana
├── init-scripts/
│   └── postgres/
│       └── 01-init-databases.sql # Script tự động tạo các DB phụ cho PostgreSQL
├── loki/
│   └── loki-config.yml        # Cấu hình lưu trữ log của Loki
├── promtail/
│   └── promtail-config.yml    # Định nghĩa cấu hình quét log container của Promtail
├── docker-compose.yml         # File Docker Compose chính định nghĩa hạ tầng
└── README.md
```

---

## 🗺️ Bản Đồ Cổng Kết Nối Ngoài (Exposed Ports)

Các dịch vụ hạ tầng sẽ mở các cổng trên host máy tính local của bạn như sau:

| Dịch vụ | Cổng Ngoài (Host Port) | Vai trò | Giao diện quản trị (Web UI) |
| :--- | :--- | :--- | :--- |
| **PostgreSQL** | `5432` | Kết nối Database lõi | pgAdmin/DBeaver |
| **MongoDB** | `27017` | Kết nối Database đấu giá | MongoDB Compass |
| **Redis** | `6379` | Kết nối Cache/Locks | RedisInsight |
| **RabbitMQ** | `5672` | Broker kết nối ứng dụng | [http://localhost:15672](http://localhost:15672) (User: `backhaulbid` / Pass: `backhaulbid_secret`) |
| **Grafana** | `3000` | Xem Logs hệ thống | [http://localhost:3000](http://localhost:3000) (User: `admin` / Pass: `backhaulbid_secret`) |
| **Loki** | `3100` | Log Aggregator | Không có UI riêng (truy cập qua Grafana) |
