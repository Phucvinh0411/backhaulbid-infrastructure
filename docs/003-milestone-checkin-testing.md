# 🧪 Hướng dẫn Test Tính năng Milestone Check-in bằng Postman

> **Tính năng:** Tài xế check-in tại các cột mốc trên hành trình vận chuyển.  
> **Kiến trúc:** Spring Boot (`contract-service`) → RabbitMQ → NestJS (`notification`) → Socket.io → Client  
> **Base URL:** `http://localhost:8080` (API Gateway)

---

## 📐 Kiến trúc luồng test

```
Postman
  │
  ▼
localhost:8080  (API Gateway — port duy nhất expose ra ngoài)
  │
  ├─ POST /api/v1/auth/login          → identity-service  (lấy JWT)
  ├─ GET  /api/v1/trips/**            → contract-service  (xem trip)
  ├─ POST /api/v1/trips/**/milestones → contract-service  (tạo cột mốc)
  └─ POST /api/v1/trips/**/checkin   → contract-service  (check-in GPS)
                                              │
                                              ▼
                                        RabbitMQ :15672
                                        exchange = contract.events
                                        queue    = trip.milestone.reached.queue
                                              │
                                              ▼
                                     notification-service :3002
                                     (NestJS RabbitMQ Consumer)
                                              │
                                              ▼
                                     Socket.io emit('milestone_updated')
                                     → room của Shipper & Carrier
```

---

## ⚙️ Bước 0 — Khởi động hệ thống

```bash
cd backhaulbid-infrastructure
docker compose up -d
```

Chờ tất cả service healthy (~2-3 phút). Kiểm tra:
```bash
docker compose ps
```

Tất cả service phải ở trạng thái `healthy` hoặc `running`.

---

## ⚙️ Bước 0.1 — Cấu hình Postman Environment

Tạo một **Environment** trong Postman tên `BackhaulBid Local` với các biến:

| Variable | Value |
|----------|-------|
| `base_url` | `http://localhost:8080` |
| `access_token` | *(để trống, sẽ tự điền)* |
| `trip_id` | *(để trống, điền sau)* |
| `milestone_id` | *(để trống, điền sau)* |

---

## 📋 Bước 1 — Đăng nhập lấy JWT (CARRIER)

> Để tạo milestone, cần tài khoản **CARRIER** (Chủ xe).

### `POST {{base_url}}/api/v1/auth/login`

**Body (raw JSON):**
```json
{
  "email": "carrier@example.com",
  "password": "your_password"
}
```

**Response:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
  "tokenType": "Bearer"
}
```

**Tự động lưu token** → Dán vào tab **Tests** của request:
```javascript
const res = pm.response.json();
if (res.accessToken) {
    pm.environment.set("access_token", res.accessToken);
    console.log("✅ Token saved!");
}
```

---

## 📋 Bước 2 — Lấy danh sách Trip đang hoạt động

### `GET {{base_url}}/api/v1/trips/mine`

**Header:**
```
Authorization: Bearer {{access_token}}
```

**Response mẫu:**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "IN_TRANSIT",
    "pickupLocation": "Hà Nội",
    "deliveryLocation": "TP.HCM"
  }
]
```

> ✏️ Sao chép `id` của trip có status `IN_TRANSIT` → lưu vào biến `trip_id`.

---

## 📋 Bước 3 — Tạo Milestone cho Trip

### `POST {{base_url}}/api/v1/trips/{{trip_id}}/milestones`

**Header:**
```
Authorization: Bearer {{access_token}}
Content-Type: application/json
```

**Body — Cột mốc 1 (Hà Nội):**
```json
{
  "milestoneName": "Kho lấy hàng Hà Nội",
  "targetLat": 21.028511,
  "targetLng": 105.804817,
  "sequenceOrder": 1
}
```

**Body — Cột mốc 2 (Đà Nẵng):**
```json
{
  "milestoneName": "Trạm dừng Đà Nẵng",
  "targetLat": 16.047079,
  "targetLng": 108.206230,
  "sequenceOrder": 2
}
```

**Body — Cột mốc 3 (TP.HCM):**
```json
{
  "milestoneName": "Kho giao hàng TP.HCM",
  "targetLat": 10.772461,
  "targetLng": 106.697966,
  "sequenceOrder": 3
}
```

**Response mẫu:**
```json
{
  "id": "7f3e8a00-1234-abcd-5678-9876543210ff",
  "tripId": "550e8400-...",
  "milestoneName": "Kho lấy hàng Hà Nội",
  "targetLat": 21.028511,
  "targetLng": 105.804817,
  "status": "PENDING",
  "sequenceOrder": 1,
  "createdAt": "2026-10-01T10:00:00Z"
}
```

> ✏️ Sao chép `id` của milestone đầu tiên → lưu vào biến `milestone_id`.

---

## 📋 Bước 4 — Xem danh sách Milestones

### `GET {{base_url}}/api/v1/trips/{{trip_id}}/milestones`

**Header:**
```
Authorization: Bearer {{access_token}}
```

**Response mẫu:**
```json
[
  {
    "id": "7f3e8a00-...",
    "milestoneName": "Kho lấy hàng Hà Nội",
    "status": "PENDING",
    "sequenceOrder": 1
  },
  {
    "id": "8a4f9b11-...",
    "milestoneName": "Trạm dừng Đà Nẵng",
    "status": "PENDING",
    "sequenceOrder": 2
  },
  {
    "id": "9b5g0c22-...",
    "milestoneName": "Kho giao hàng TP.HCM",
    "status": "PENDING",
    "sequenceOrder": 3
  }
]
```

---

## 📋 Bước 5 — Đăng nhập lại bằng tài khoản DRIVER

> Lặp lại **Bước 1** với tài khoản có role = `DRIVER` (Tài xế).

---

## 📋 Bước 6 — Test Check-in (Core Feature)

### `POST {{base_url}}/api/v1/trips/{{trip_id}}/milestones/{{milestone_id}}/checkin`

**Header:**
```
Authorization: Bearer {{access_token}}
Content-Type: application/json
```

---

### ✅ Test Case 1 — Check-in HỢP LỆ (trong vòng 2km)

Tọa độ mục tiêu: `21.028511, 105.804817` (Hà Nội)  
Tọa độ giả lập: cách ~0.5km

**Body:**
```json
{
  "currentLat": 21.033000,
  "currentLng": 105.808000
}
```

**✅ Kết quả mong đợi — HTTP 200:**
```json
{
  "id": "7f3e8a00-...",
  "milestoneName": "Kho lấy hàng Hà Nội",
  "actualLat": 21.033000,
  "actualLng": 105.808000,
  "status": "REACHED",
  "reachedAt": "2026-10-01T10:15:00Z"
}
```

---

### ❌ Test Case 2 — Geo-fencing CHẶN (ngoài 2km)

Tọa độ mục tiêu: Hà Nội  
Tọa độ giả lập: TP.HCM (cách ~1734km)

**Body:**
```json
{
  "currentLat": 10.762622,
  "currentLng": 106.660172
}
```

**❌ Kết quả mong đợi — HTTP 400:**
```json
{
  "status": 400,
  "message": "Vị trí không hợp lệ. Bạn đang ở quá xa cột mốc! (Khoảng cách hiện tại: 1734.XX km, cho phép: 2.0 km)"
}
```

---

### ❌ Test Case 3 — Check-in milestone đã REACHED

Sau Test Case 1, gọi lại cùng request đó.

**❌ Kết quả mong đợi — HTTP 409:**
```json
{
  "status": 409,
  "message": "Milestone has already been reached"
}
```

---

### ❌ Test Case 4 — Thiếu field bắt buộc

**Body:**
```json
{
  "currentLat": 21.033000
}
```

**❌ Kết quả mong đợi — HTTP 400 (Validation):**
```json
{
  "status": 400,
  "message": "currentLng: must not be null"
}
```

---

### ✅ Test Case 5 — Tọa độ sát ngưỡng 2km

**Body (cách đúng ~2.0km về phía Bắc):**
```json
{
  "currentLat": 21.046510,
  "currentLng": 105.804817
}
```

**✅ Kết quả mong đợi — HTTP 200** (vừa đủ ≤ 2km)

---

## 📋 Bước 7 — Xác nhận RabbitMQ nhận event

Sau khi **Test Case 1** thành công:

1. Mở trình duyệt: `http://localhost:15672`
2. Đăng nhập: username/password từ file `.env` (`RABBITMQ_USER` / `RABBITMQ_PASSWORD`)
3. Vào **Queues and Streams** → tìm queue `trip.milestone.reached.queue`
4. Cột **Messages** hiển thị `0` → NestJS consumer đã xử lý thành công ✅
5. Cột **Messages** còn > 0 → notification-service chưa chạy hoặc có lỗi ❌

---

## 📋 Bước 8 — Kiểm tra Socket.io realtime (Nâng cao)

Dùng Postman WebSocket để lắng nghe event realtime:

1. Postman → **New** → **WebSocket**
2. URL: `ws://localhost:8080/notification-socket`
3. Kết nối → chờ event `milestone_updated`

Khi tài xế check-in thành công, Shipper và Carrier sẽ nhận event:
```json
{
  "milestoneId": "7f3e8a00-...",
  "tripId": "550e8400-...",
  "milestoneName": "Kho lấy hàng Hà Nội",
  "status": "REACHED",
  "location": { "lat": 21.033000, "lng": 105.808000 },
  "reachedAt": "2026-10-01T10:15:00Z"
}
```

---

## 🗺️ Bảng tọa độ Việt Nam để test Haversine

| Địa điểm | Lat | Lng | Cách HN (km) |
|----------|-----|-----|--------------|
| Hà Nội (mục tiêu) | 21.028511 | 105.804817 | 0 |
| Cách HN ~0.5km (PASS ✅) | 21.033000 | 105.808000 | ~0.5 |
| Cách HN ~1.9km (PASS ✅) | 21.045600 | 105.804817 | ~1.9 |
| Cách HN ~2.5km (FAIL ❌) | 21.051100 | 105.804817 | ~2.5 |
| Đà Nẵng (FAIL ❌) | 16.047079 | 108.206230 | ~764 |
| TP.HCM (FAIL ❌) | 10.762622 | 106.660172 | ~1734 |

> **Công thức nhanh:** 1 độ vĩ độ ≈ 111 km → 2 km ≈ 0.018 độ lat

---

## 📊 Tóm tắt tất cả API Endpoints

| Method | Endpoint | Role | Mô tả |
|--------|----------|------|-------|
| `POST` | `/api/v1/auth/login` | Public | Đăng nhập lấy JWT |
| `GET` | `/api/v1/trips/mine` | Any | Lấy danh sách trips của mình |
| `POST` | `/api/v1/trips/{tripId}/milestones` | CARRIER | Tạo cột mốc mới |
| `GET` | `/api/v1/trips/{tripId}/milestones` | Any | Xem danh sách cột mốc |
| `POST` | `/api/v1/trips/{tripId}/milestones/{milestoneId}/checkin` | DRIVER | ⭐ Check-in tại cột mốc |

---

## 🚨 Troubleshooting

| Lỗi | Nguyên nhân | Giải pháp |
|-----|-------------|-----------|
| `401 Unauthorized` | JWT hết hạn hoặc thiếu | Đăng nhập lại, lấy token mới |
| `403 Forbidden` | Sai role (CARRIER gọi checkin) | Dùng đúng tài khoản DRIVER |
| `404 Not Found` | tripId hoặc milestoneId sai | Kiểm tra lại UUID từ Bước 2-3 |
| `400` "Vị trí không hợp lệ" | Tọa độ ngoài 2km | Dùng tọa độ gần mục tiêu hơn |
| `409 Conflict` | Milestone đã REACHED | Dùng milestone khác chưa check-in |
| RabbitMQ queue tích đọng | notification-service không chạy | `docker compose up -d notification-service` |
| Gateway trả 503 | contract-service chưa đăng ký Eureka | Đợi thêm 30s hoặc restart service |
