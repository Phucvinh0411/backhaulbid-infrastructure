# ADR-001: Gateway là trust boundary cho danh tính người dùng

## Trạng thái

Accepted

## Ngày

2026-07-31

## Bối cảnh

Web portal dùng JWT trong HttpOnly cookie. Các core service cần biết account và
role hiện tại, nhưng không được tin `accountId` trong request body hoặc các
header do browser tự gửi. Đồng thời các route phải dùng service discovery để
không phụ thuộc địa chỉ container cố định.

## Quyết định

API Gateway:

- đọc JWT từ cookie `accessToken`, sau đó mới fallback sang Bearer token;
- xác minh chữ ký trước khi định tuyến request được bảo vệ;
- luôn xóa `X-User-Id` và `X-User-Role` từ request gốc;
- tạo lại hai header trên từ JWT đã xác minh;
- định tuyến core services bằng Eureka và `lb://`.

Identity service tạo `Authentication` từ header nội bộ. eKYC lấy account từ
`Authentication.getName()` và không nhận `accountId` do client cung cấp.

Gateway readiness chỉ `UP` khi discovery cache có instance cho mọi core route,
tránh trả 503 trong cửa sổ đồng bộ registry lúc cold start.

## Phương án đã cân nhắc

### Mỗi service tự parse JWT

An toàn nhưng lặp cấu hình khóa, parser và chính sách public route ở từng
service. Khi thay đổi auth, nhiều service phải phát hành đồng thời.

### Tin header từ client

Đơn giản nhưng cho phép giả mạo account/role, nên bị loại bỏ.

### Gửi accountId trong body eKYC

Cho phép người dùng ghi dữ liệu eKYC vào account khác, nên bị loại bỏ.

## Hệ quả

- Gateway và identity service phải dùng cùng `JWT_SECRET`.
- Core services chỉ nên được expose trực tiếp để debug local; production network
  phải giới hạn ingress qua gateway.
- Các public route mới phải được khai báo rõ trong gateway filter.
- Thay đổi JWT claim cần test đồng thời gateway và identity service.
