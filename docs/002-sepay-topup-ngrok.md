# 002 — Nạp tiền ví qua SePay sandbox với ngrok

## Mục đích

Môi trường phát triển chạy trên `localhost` nên SePay sandbox không thể gọi IPN
(server-to-server callback) về máy dev. Tài liệu này mô tả cách dùng **ngrok** để
public API Gateway ra internet, cho phép luồng nạp tiền ví hoạt động end-to-end:

```
Chủ xe (browser :3000)
   │  1. POST /api/v1/payments/sepay/top-ups  (tạo đơn nạp)
   ▼
API Gateway :8080 ──────────────► wallet-service :8083
   │  2. wallet-service gọi checkout SePay sandbox → trả payment URL
   ▼
Chủ xe chuyển khoản trên trang SePay sandbox
   │  3. SePay gọi IPN: POST https://<id>.ngrok-free.app/api/v1/payments/sepay/ipn
   ▼
ngrok ──► Gateway :8080 ──► wallet-service (verify X-Secret-Key, ghi có ví)
   │  4. Frontend poll GET /api/v1/payments/sepay/top-ups/{invoiceNumber}
   ▼
Ví cập nhật số dư (PAID)
```

## Yêu cầu

1. Tài khoản ngrok và auth token: `ngrok config add-authtoken <token>`
2. Stack backend đang chạy (Docker compose hoặc chạy tay):
   - `api-gateway` :8080
   - `wallet-service` :8083 (đăng ký Eureka)
   - `eureka-server`, `identity-service` (JWT cho frontend)
3. Frontend `fe/backhaulbid-web-portal` chạy ở :3000.
4. Tài khoản merchant sandbox SePay (merchant id + secret key).

## Biến môi trường wallet-service

| Biến | Giá trị gợi ý | Ý nghĩa |
|------|---------------|---------|
| `SEPAY_ENABLED` | `true` | Bật tích hợp SePay |
| `SEPAY_MERCHANT_ID` | merchant id sandbox | Định danh merchant |
| `SEPAY_SECRET_KEY` | secret key sandbox | Ký/verify checkout |
| `SEPAY_IPN_SECRET` | giống secret key | Verify header `X-Secret-Key` của IPN |
| `SEPAY_CHECKOUT_URL` | `https://pay-sandbox.sepay.vn/v1/checkout/init` | API checkout sandbox |
| `SEPAY_SUCCESS_URL` | `http://localhost:8080/carrier/wallet?payment=success` | Redirect sau thanh toán |
| `SEPAY_ERROR_URL` | `http://localhost:8080/carrier/wallet?payment=error` | Redirect khi lỗi |
| `SEPAY_CANCEL_URL` | `http://localhost:8080/carrier/wallet?payment=cancel` | Redirect khi hủy |

> Success/error/cancel URL là redirect phía browser của chủ xe nên trỏ về
> `localhost:8080` (API Gateway — catch-all route proxy sang web-portal, dùng khi
> chạy Docker). Không cần ngrok cho các URL này; chỉ **IPN** mới cần URL public.
> Nếu chạy frontend bằng `npm run dev` thuần (không Docker), đổi sang `localhost:3000`.

## Các bước thực hiện

### 1. Chạy ngrok trỏ vào API Gateway

```powershell
ngrok http 8080
```

Ngrok in ra URL dạng `https://abcd1234.ngrok-free.app`. Giữ terminal này chạy suốt
quá trình test. Mỗi lần restart ngrok (gói free) URL có thể đổi → phải cập nhật
lại IPN URL ở bước 2.

Có thể dùng script tự động: `scripts/ngrok-topup.ps1` (trong repo này).

### 2. Cấu hình IPN trên SePay sandbox

Trong trang quản trị merchant sandbox SePay, đặt:

- **IPN URL**: `https://<id>.ngrok-free.app/api/v1/payments/sepay/ipn`
- **Secret Key**: khớp với `SEPAY_IPN_SECRET` của wallet-service.

Gateway đã whitelist path `/api/v1/payments/sepay/ipn` khỏi JWT filter
(`JwtGlobalFilter`), SePay xác thực bằng header `X-Secret-Key`.

### 3. Test nhanh IPN bằng curl

Payload IPN theo contract `SepayIpnRequest` của wallet-service:

```bash
curl -X POST "https://<id>.ngrok-free.app/api/v1/payments/sepay/ipn" `
  -H "Content-Type: application/json" `
  -H "X-Secret-Key: <SEPAY_IPN_SECRET>" `
  -d '{
    "timestamp": 1755338400,
    "notification_type": "ORDER_PAID",
    "order": {
      "order_invoice_number": "<invoiceNumber>",
      "order_status": "PAID",
      "order_amount": "500000"
    },
    "transaction": {
      "transaction_id": "TEST-TXN-001",
      "transaction_status": "SUCCESS",
      "transaction_amount": "500000"
    }
  }'
```

Thay `<invoiceNumber>` bằng số hóa đơn của đơn nạp (hiển thị trên màn hình ví),
`order_amount`/`transaction_amount` phải **khớp đúng** số tiền của đơn (VND, số nguyên dương).
Response `200` và trạng thái đơn chuyển `PAID` là đạt.

- `notification_type = ORDER_PAID` → ghi có ví, đơn chuyển `PAID`.
- `notification_type = TRANSACTION_VOID` → đơn chuyển `EXPIRED` (hoàn/hủy giao dịch).
- IPN gọi lại nhiều lần vẫn an toàn (idempotent — đơn đã `PAID` được bỏ qua).

### 4. Test luồng đầy đủ trên UI

1. Đăng nhập chủ xe → trang Ví → chọn "Nạp tiền", nhập số tiền.
2. Hệ thống tạo đơn + mở trang thanh toán SePay sandbox.
3. Chuyển khoản theo hướng dẫn sandbox (hoặc simulate giao dịch trên SePay).
4. Quay về `/carrier/wallet?payment=success`; frontend poll trạng thái đơn mỗi 4s.
5. Đơn `PAID` → ví tự reload số dư, hiện thông báo nạp tiền thành công.

## Xử lý sự cố

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|-------------|------------------------|------------|
| SePay báo IPN failed | ngrok chưa chạy / URL đổi | Chạy lại `ngrok http 8080`, cập nhật IPN URL |
| IPN 401 | `X-Secret-Key` lệch `SEPAY_IPN_SECRET` | Đồng bộ secret hai bên |
| IPN 400 "Unsupported notification" | `notification_type` không phải `ORDER_PAID` | Kiểm tra cấu hình sandbox |
| IPN 422 "amount does not match" | Số tiền chuyển khác số tiền đơn | Chuyển đúng số tiền đơn yêu cầu |
| IPN 404 | Gateway chưa route `/api/v1/payments/sepay/**` | Kiểm tra route `wallet-service` trong `application.yml` gateway |
| Đơn đứng `PENDING` dù đã PAID | wallet-service chưa nhận IPN | Xem log wallet-service, test curl bước 3 |
| Frontend không cập nhật | cookie JWT hết hạn / poll lỗi | F5 trang ví, đăng nhập lại |