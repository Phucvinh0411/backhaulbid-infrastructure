/**
 * Seed data script for BackhaulBid
 * Generates comprehensive test data covering ALL auction & shipment lifecycle phases:
 *  - Phase 0: WAITING_REG (Chờ mở đăng ký)
 *  - Phase 1: REGISTERING (Đang mở đăng ký tham gia)
 *  - Phase 2: WAITING_AUCTION (Chờ giờ bắt đầu đấu giá)
 *  - Phase 3 (Active): BIDDING_ACTIVE (Đang đấu giá sôi nổi với nhiều lượt bid)
 *  - Phase 3 (Empty): BIDDING_NO_BIDS (Đang đấu giá mới mở, chưa có ai đặt giá)
 *  - Phase 4 (Awarded): CLOSED_AWARDED (Đã đóng thầu, có người thắng)
 *  - Phase 4 (No Bids): CLOSED_NO_BIDS (Đã đóng thầu nhưng không ai tham gia)
 *  - Cancelled: CANCELLED (Phiên bị hủy với lý do cụ thể)
 *  - Shipping: SHIPPING (Đang vận chuyển trên đường)
 */

const now = new Date();
const ms = (hours) => hours * 60 * 60 * 1000;
const min = (m) => m * 60 * 1000;

const SHIPPER_1 = "44444444-4444-4444-4444-444444444444"; // Nguyễn Văn Hàng (Shipper)
const SHIPPER_2 = "33333333-3333-3333-3333-333333333333"; // Demo Shipper

const CARRIER_1 = "55555555-5555-5555-5555-555555555555"; // Công Ty Vận Tải Hàng Xe Việt Nam
const CARRIER_2 = "22222222-2222-2222-2222-222222222222"; // Công Ty CP Logistics Toàn Cầu LogiTrans

const VEHICLE_CARRIER_1 = "55555555-0000-0000-0000-000000000002"; // 51D-999.99 (CONTAINER_TRACTOR)
const VEHICLE_CARRIER_1_REF = "55555555-0000-0000-0000-000000000003"; // 50H-123.45 (REFRIGERATED_TRUCK)
const VEHICLE_CARRIER_1_HEAVY = "55555555-0000-0000-0000-000000000004"; // 51E-777.77 (TRUCK_HEAVY)

const VEHICLE_CARRIER_2_HEAVY = "22222222-0000-0000-0000-000000000001"; // 29C-111.22 (TRUCK_HEAVY)
const VEHICLE_CARRIER_2_TRACTOR = "22222222-0000-0000-0000-000000000002"; // 29D-333.44 (CONTAINER_TRACTOR)
const VEHICLE_CARRIER_2_MED = "22222222-0000-0000-0000-000000000004"; // 29E-777.88 (TRUCK_MEDIUM)

// Clear existing seeded data to avoid duplication
db.auctions.deleteMany({ _id: { $regex: /^seed-/ } });
db.auction_registrations.deleteMany({ _id: { $regex: /^seed-reg-/ } });
db.bids.deleteMany({ _id: { $regex: /^seed-bid-/ } });

const auctions = [
  // ==========================================
  // CASE 1: Phase 0 - CHỜ MỞ ĐĂNG KÝ (WAITING_REG)
  // now < regStartTime
  // ==========================================
  {
    _id: "seed-auc-01-phase0-waiting-reg",
    shipperId: SHIPPER_1,
    title: "15 Tấn Thiết Bị Viễn Thông & Linh Kiện Server 5G",
    goodsType: "Thiết bị công nghệ điện tử",
    weight: 15.0,
    volume: 35.0,
    goodsValue: NumberDecimal("850000000.00"),
    vehicleTypeRequired: "TRUCK_HEAVY",
    vehicleSpecs: { length: 9.6, width: 2.4, height: 2.6 },
    origin: "TP. Hồ Chí Minh - KCN Tân Bình",
    destination: "Đà Nẵng - KCN Hòa Cầm",
    pickupLocation: {
      locationName: "Tổng Kho KCN Tân Bình",
      province: "TP. Hồ Chí Minh",
      address: "Lô II-3, Đường số 11, KCN Tân Bình, P. Tây Thạnh, Q. Tân Phú",
      contactName: "Trần Anh Tuấn (Kho)",
      contactPhone: "0912345678",
      earliestTime: new Date(now.getTime() + ms(26)),
      latestTime: new Date(now.getTime() + ms(32))
    },
    deliveryLocation: {
      locationName: "Trung Tâm Dữ Liệu Hòa Cầm",
      province: "Đà Nẵng",
      address: "Đường số 4, KCN Hòa Cầm, P. Hòa Thọ Tây, Q. Cẩm Lệ",
      contactName: "Phạm Văn Minh",
      contactPhone: "0987654321",
      earliestTime: new Date(now.getTime() + ms(48)),
      latestTime: new Date(now.getTime() + ms(56))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("18500000.00"),
    priceStep: NumberDecimal("200000.00"),
    maxBids: 20,
    images: [
      "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?w=800&auto=format&fit=crop"
    ],
    notes: "Hàng linh kiện điện tử giá trị cao, bắt buộc xe thùng kín có bảo hiểm hàng hóa.",
    isDepositRequired: true,
    depositAmount: NumberDecimal("1000000.00"),
    participationFeeTier: "LEVEL_2",
    participationFeeAmount: NumberDecimal("50000.00"),
    creationFeeTier: "LEVEL_2",
    creationFeeAmount: NumberDecimal("100000.00"),
    creationIdempotencyKey: "seed-key-01",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-01",
    creationFeeTransactionId: "seed-tx-01",
    registrationStartTime: new Date(now.getTime() + ms(2)), // Mở đăng ký sau 2 tiếng
    registrationEndTime: new Date(now.getTime() + ms(10)), // Đóng đăng ký sau 10 tiếng
    startTime: new Date(now.getTime() + ms(12)),            // Bắt đầu đấu giá sau 12 tiếng
    endTime: new Date(now.getTime() + ms(24)),              // Kết thúc đấu giá sau 24 tiếng
    status: "PENDING",
    winningBidId: null,
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(1)),
    updatedAt: new Date(now.getTime() - ms(1))
  },

  // ==========================================
  // CASE 2: Phase 1 - ĐANG MỞ ĐĂNG KÝ (REGISTERING)
  // regStartTime <= now < regEndTime
  // ==========================================
  {
    _id: "seed-auc-02-phase1-registering",
    shipperId: SHIPPER_1,
    title: "20 Tấn Nông Sản Sầu Riêng Ri6 Đắk Lắk Xuất Khẩu",
    goodsType: "Hàng nông sản / Đông lạnh",
    weight: 20.0,
    volume: 42.0,
    goodsValue: NumberDecimal("1200000000.00"),
    vehicleTypeRequired: "REFRIGERATED_TRUCK",
    requiredTemp: "-18°C đến -22°C",
    vehicleSpecs: { length: 12.0, width: 2.45, height: 2.6 },
    origin: "Đắk Lắk - Hợp Tác Xã Sầu Riêng Krông Pắk",
    destination: "Hải Phòng - Cảng Đình Vũ",
    pickupLocation: {
      locationName: "Vựa Thu Mua Krông Pắk",
      province: "Đắk Lắk",
      address: "Km 25, Quốc Lộ 26, Xã Ea Yông, Huyện Krông Pắk",
      contactName: "Nguyễn Văn Sang",
      contactPhone: "0908112233",
      earliestTime: new Date(now.getTime() + ms(20)),
      latestTime: new Date(now.getTime() + ms(28))
    },
    deliveryLocation: {
      locationName: "Kho Ngoại Quan Cảng Đình Vũ",
      province: "Hải Phòng",
      address: "Khu Kinh Tế Đình Vũ, P. Đông Hải 2, Q. Hải An",
      contactName: "Đỗ Thanh Hùng",
      contactPhone: "0938445566",
      earliestTime: new Date(now.getTime() + ms(50)),
      latestTime: new Date(now.getTime() + ms(60))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("32000000.00"),
    priceStep: NumberDecimal("500000.00"),
    maxBids: 15,
    images: [
      "https://images.unsplash.com/photo-1595246140625-573b715d11dc?w=800&auto=format&fit=crop"
    ],
    notes: "Yêu cầu duy trì nhiệt độ âm sâu -18°C suốt hành trình, theo dõi định vị nhiệt độ liên tục.",
    isDepositRequired: true,
    depositAmount: NumberDecimal("2000000.00"),
    participationFeeTier: "LEVEL_3",
    participationFeeAmount: NumberDecimal("100000.00"),
    creationFeeTier: "LEVEL_3",
    creationFeeAmount: NumberDecimal("200000.00"),
    creationIdempotencyKey: "seed-key-02",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-02",
    creationFeeTransactionId: "seed-tx-02",
    registrationStartTime: new Date(now.getTime() - ms(3)), // Đã mở đăng ký 3 tiếng trước
    registrationEndTime: new Date(now.getTime() + ms(5)),  // Còn 5 tiếng nữa đóng đăng ký
    startTime: new Date(now.getTime() + ms(7)),             // Bắt đầu sau 7 tiếng
    endTime: new Date(now.getTime() + ms(19)),              // Kết thúc sau 19 tiếng
    status: "PENDING",
    winningBidId: null,
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(4)),
    updatedAt: new Date(now.getTime() - ms(1))
  },

  // ==========================================
  // CASE 3: Phase 2 - CHỜ BẮT ĐẦU ĐẤU GIÁ (WAITING_AUCTION)
  // regEndTime <= now < startTime
  // ==========================================
  {
    _id: "seed-auc-03-phase2-waiting-auction",
    shipperId: SHIPPER_1,
    title: "25 Tấn Thép Xây Dựng Dự Án Cầu Cần Thơ 2",
    goodsType: "Vật liệu xây dựng & Kết cấu thép",
    weight: 25.0,
    volume: 18.0,
    goodsValue: NumberDecimal("450000000.00"),
    vehicleTypeRequired: "TRUCK_HEAVY",
    vehicleSpecs: { length: 12.5, width: 2.4, height: 2.4 },
    origin: "Bình Dương - KCN Sóng Thần 2",
    destination: "Cần Thơ - KCN Trà Nóc",
    pickupLocation: {
      locationName: "Nhà Máy Thép Pomina Sóng Thần",
      province: "Bình Dương",
      address: "Đường số 3, KCN Sóng Thần 2, TP. Dĩ An",
      contactName: "Lê Quốc Bảo",
      contactPhone: "0903334455",
      earliestTime: new Date(now.getTime() + ms(10)),
      latestTime: new Date(now.getTime() + ms(16))
    },
    deliveryLocation: {
      locationName: "Kho Dự Án Cầu Cần Thơ 2",
      province: "Cần Thơ",
      address: "Đường Lê Hồng Phong, KCN Trà Nóc 1, Q. Bình Thủy",
      contactName: "Trương Định",
      contactPhone: "0918889900",
      earliestTime: new Date(now.getTime() + ms(24)),
      latestTime: new Date(now.getTime() + ms(30))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("14500000.00"),
    priceStep: NumberDecimal("150000.00"),
    maxBids: 15,
    images: [
      "https://images.unsplash.com/photo-1504917599217-d4dc5ebe6122?w=800&auto=format&fit=crop"
    ],
    notes: "Xe tải nặng sàn phẳng có dây xích chằng buộc cẩn thận, vào kho phải có mũ bảo hộ lao động.",
    isDepositRequired: false,
    depositAmount: null,
    participationFeeTier: "LEVEL_2",
    participationFeeAmount: NumberDecimal("50000.00"),
    creationFeeTier: "LEVEL_2",
    creationFeeAmount: NumberDecimal("100000.00"),
    creationIdempotencyKey: "seed-key-03",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-03",
    creationFeeTransactionId: "seed-tx-03",
    registrationStartTime: new Date(now.getTime() - ms(8)), // Đã mở từ 8h trước
    registrationEndTime: new Date(now.getTime() - ms(1)),   // Đã đóng 1h trước
    startTime: new Date(now.getTime() + ms(1.5)),          // Còn 1.5h nữa bắt đầu đấu giá!
    endTime: new Date(now.getTime() + ms(8)),               // Kết thúc sau 8h
    status: "PENDING",
    winningBidId: null,
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(9)),
    updatedAt: new Date(now.getTime() - ms(1))
  },

  // ==========================================
  // CASE 4: Phase 3 - ĐANG ĐẤU GIÁ SÔI NỔI (BIDDING_ACTIVE)
  // startTime <= now < endTime, có 4 bids giảm dần
  // ==========================================
  {
    _id: "seed-auc-04-phase3-bidding-active",
    shipperId: SHIPPER_1,
    title: "30 Tấn Hàng Tiêu Dùng FMCG Phân Phối Siêu Thị Toàn Quốc",
    goodsType: "Hàng tiêu dùng đóng thùng",
    weight: 30.0,
    volume: 68.0,
    goodsValue: NumberDecimal("620000000.00"),
    vehicleTypeRequired: "CONTAINER_TRACTOR",
    vehicleSpecs: { length: 14.5, width: 2.5, height: 2.7 },
    origin: "Đồng Nai - KCN Amata Biên Hòa",
    destination: "Hà Nội - KCN Quang Minh Mê Linh",
    pickupLocation: {
      locationName: "Tổng Kho Phân Phối Amata",
      province: "Đồng Nai",
      address: "Khu Phố 3, P. Long Bình, TP. Biên Hòa",
      contactName: "Đặng Hoàng Giang",
      contactPhone: "0917772211",
      earliestTime: new Date(now.getTime() + ms(14)),
      latestTime: new Date(now.getTime() + ms(20))
    },
    deliveryLocation: {
      locationName: "Hub Trung Chuyển Miền Bắc Quang Minh",
      province: "Hà Nội",
      address: "Lô 38B, KCN Quang Minh, Huyện Mê Linh",
      contactName: "Ngô Đức Trọng",
      contactPhone: "0904445566",
      earliestTime: new Date(now.getTime() + ms(50)),
      latestTime: new Date(now.getTime() + ms(58))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("28000000.00"),
    priceStep: NumberDecimal("200000.00"),
    maxBids: 30,
    images: [
      "https://images.unsplash.com/photo-1580674684081-7617fbf3d745?w=800&auto=format&fit=crop"
    ],
    notes: "Xe đầu kéo container 40 feet kín nước, tài xế có đầy đủ giấy khám sức khỏe và CCCD.",
    isDepositRequired: true,
    depositAmount: NumberDecimal("1500000.00"),
    participationFeeTier: "LEVEL_3",
    participationFeeAmount: NumberDecimal("100000.00"),
    creationFeeTier: "LEVEL_3",
    creationFeeAmount: NumberDecimal("200000.00"),
    creationIdempotencyKey: "seed-key-04",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-04",
    creationFeeTransactionId: "seed-tx-04",
    registrationStartTime: new Date(now.getTime() - ms(12)),
    registrationEndTime: new Date(now.getTime() - ms(2)),
    startTime: new Date(now.getTime() - min(45)),           // Đã mở đấu giá 45 phút trước
    endTime: new Date(now.getTime() + min(75)),             // Còn 75 phút đấu giá!
    status: "OPEN",
    winningBidId: null,
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(13)),
    updatedAt: new Date(now.getTime() - min(2))
  },

  // ==========================================
  // CASE 5: Phase 3 - ĐANG ĐẤU GIÁ MỚI MỞ, CHƯA CÓ BID (BIDDING_NO_BIDS)
  // startTime <= now < endTime, 0 bids
  // ==========================================
  {
    _id: "seed-auc-05-phase3-bidding-no-bids",
    shipperId: SHIPPER_1,
    title: "8 Tấn Vải Cuộn & Phụ Liệu May Mặc Xuất Khẩu Sang Nhật",
    goodsType: "Hàng may mặc thời trang",
    weight: 8.0,
    volume: 24.0,
    goodsValue: NumberDecimal("380000000.00"),
    vehicleTypeRequired: "TRUCK_MEDIUM",
    vehicleSpecs: { length: 7.2, width: 2.3, height: 2.3 },
    origin: "Long An - KCN Thuận Đạo Bến Lức",
    destination: "Đà Nẵng - KCN Hòa Khánh",
    pickupLocation: {
      locationName: "Xưởng May Dệt Thuận Đạo",
      province: "Long An",
      address: "Đường số 10, KCN Thuận Đạo, Thị trấn Bến Lức",
      contactName: "Bùi Thị Mai",
      contactPhone: "0933556677",
      earliestTime: new Date(now.getTime() + ms(8)),
      latestTime: new Date(now.getTime() + ms(14))
    },
    deliveryLocation: {
      locationName: "Kho Vải Thành Phẩm Hòa Khánh",
      province: "Đà Nẵng",
      address: "Đường số 2, KCN Hòa Khánh, Q. Liên Chiểu",
      contactName: "Vũ Minh Quân",
      contactPhone: "0977889900",
      earliestTime: new Date(now.getTime() + ms(30)),
      latestTime: new Date(now.getTime() + ms(36))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("12000000.00"),
    priceStep: NumberDecimal("100000.00"),
    maxBids: 10,
    images: [
      "https://images.unsplash.com/photo-1606760227091-3dd870d97f1d?w=800&auto=format&fit=crop"
    ],
    notes: "Xe tải thùng kín sạch sẽ, không có mùi lạ và chống ẩm tuyệt đối.",
    isDepositRequired: false,
    depositAmount: null,
    participationFeeTier: "LEVEL_2",
    participationFeeAmount: NumberDecimal("50000.00"),
    creationFeeTier: "LEVEL_2",
    creationFeeAmount: NumberDecimal("100000.00"),
    creationIdempotencyKey: "seed-key-05",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-05",
    creationFeeTransactionId: "seed-tx-05",
    registrationStartTime: new Date(now.getTime() - ms(6)),
    registrationEndTime: new Date(now.getTime() - ms(1)),
    startTime: new Date(now.getTime() - min(15)),           // Vừa bắt đầu 15 phút trước
    endTime: new Date(now.getTime() + min(45)),             // Còn 45 phút
    status: "OPEN",
    winningBidId: null,
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(7)),
    updatedAt: new Date(now.getTime() - min(15))
  },

  // ==========================================
  // CASE 6: Phase 4 - ĐÃ ĐÓNG THẦU & CÓ NGƯỜI THẮNG (CLOSED_AWARDED)
  // endTime < now, có winningBidId
  // ==========================================
  {
    _id: "seed-auc-06-phase4-closed-awarded",
    shipperId: SHIPPER_1,
    title: "16 Tấn Máy Móc CNC & Dây Chuyền Cơ Khí Chính Xác",
    goodsType: "Máy móc công nghiệp nặng",
    weight: 16.0,
    volume: 32.0,
    goodsValue: NumberDecimal("1500000000.00"),
    vehicleTypeRequired: "TRUCK_HEAVY",
    vehicleSpecs: { length: 9.8, width: 2.4, height: 2.6 },
    origin: "TP. Hồ Chí Minh - KCN Cát Lái",
    destination: "Bắc Ninh - KCN VSIP Bắc Ninh",
    pickupLocation: {
      locationName: "Kho Xuất Cát Lái",
      province: "TP. Hồ Chí Minh",
      address: "Cụm 2, KCN Cát Lái, P. Thạnh Mỹ Lợi, TP. Thủ Đức",
      contactName: "Nguyễn Thanh Phong",
      contactPhone: "0909123456",
      earliestTime: new Date(now.getTime() - ms(1)),
      latestTime: new Date(now.getTime() + ms(4))
    },
    deliveryLocation: {
      locationName: "Nhà Máy Lắp Ráp VSIP Bắc Ninh",
      province: "Bắc Ninh",
      address: "Số 8 Đại lộ Hữu Nghị, KCN VSIP, Thị xã Từ Sơn",
      contactName: "Trịnh Gia Huy",
      contactPhone: "0988776655",
      earliestTime: new Date(now.getTime() + ms(36)),
      latestTime: new Date(now.getTime() + ms(42))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("25000000.00"),
    priceStep: NumberDecimal("300000.00"),
    maxBids: 20,
    images: [
      "https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=800&auto=format&fit=crop"
    ],
    notes: "Hàng máy móc chính xác, bốc xếp bằng cẩu chuyên dụng hai đầu kho.",
    isDepositRequired: true,
    depositAmount: NumberDecimal("2000000.00"),
    participationFeeTier: "LEVEL_3",
    participationFeeAmount: NumberDecimal("100000.00"),
    creationFeeTier: "LEVEL_3",
    creationFeeAmount: NumberDecimal("200000.00"),
    creationIdempotencyKey: "seed-key-06",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-06",
    creationFeeTransactionId: "seed-tx-06",
    registrationStartTime: new Date(now.getTime() - ms(24)),
    registrationEndTime: new Date(now.getTime() - ms(14)),
    startTime: new Date(now.getTime() - ms(12)),
    endTime: new Date(now.getTime() - ms(3)),               // Đã kết thúc 3 giờ trước
    status: "COMPLETED",
    winningBidId: "seed-bid-06-03", // Trúng thầu bởi Carrier 1
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(25)),
    updatedAt: new Date(now.getTime() - ms(3))
  },

  // ==========================================
  // CASE 7: Phase 4 - ĐÃ ĐÓNG THẦU NHƯNG KHÔNG CÓ AI ĐẶT GIÁ (CLOSED_NO_BIDS)
  // endTime < now, winningBidId = null
  // ==========================================
  {
    _id: "seed-auc-07-phase4-closed-no-bids",
    shipperId: SHIPPER_1,
    title: "10 Tấn Cây Giống Lâm Nghiệp & Phân Bón Vi Sinh",
    goodsType: "Nông sản & Cây trồng",
    weight: 10.0,
    volume: 30.0,
    goodsValue: NumberDecimal("180000000.00"),
    vehicleTypeRequired: "SPECIALIZED_TRUCK",
    vehicleSpecs: { length: 8.5, width: 2.3, height: 2.4 },
    origin: "Cà Mau - Xã Tân Thành",
    destination: "Hà Giang - Huyện Mèo Vạc",
    pickupLocation: {
      locationName: "Vườn Ươm Cây Giống Cà Mau",
      province: "Cà Mau",
      address: "Ấp 3, Xã Tân Thành, TP. Cà Mau",
      contactName: "Lâm Văn Tươi",
      contactPhone: "0915667788",
      earliestTime: new Date(now.getTime() - ms(10)),
      latestTime: new Date(now.getTime() - ms(4))
    },
    deliveryLocation: {
      locationName: "Trạm Kiểm Lâm Mèo Vạc",
      province: "Hà Giang",
      address: "Tổ 2, Thị trấn Mèo Vạc, Huyện Mèo Vạc",
      contactName: "Trần Văn Sơn",
      contactPhone: "0944332211",
      earliestTime: new Date(now.getTime() + ms(20)),
      latestTime: new Date(now.getTime() + ms(28))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("15000000.00"),
    priceStep: NumberDecimal("200000.00"),
    maxBids: 10,
    images: [],
    notes: "Tuyến đường đèo dốc hiểm trở, yêu cầu xe có tời kéo và lái xe giàu kinh nghiệm đường núi.",
    isDepositRequired: false,
    depositAmount: null,
    participationFeeTier: "LEVEL_2",
    participationFeeAmount: NumberDecimal("50000.00"),
    creationFeeTier: "LEVEL_2",
    creationFeeAmount: NumberDecimal("100000.00"),
    creationIdempotencyKey: "seed-key-07",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-07",
    creationFeeTransactionId: "seed-tx-07",
    registrationStartTime: new Date(now.getTime() - ms(48)),
    registrationEndTime: new Date(now.getTime() - ms(30)),
    startTime: new Date(now.getTime() - ms(28)),
    endTime: new Date(now.getTime() - ms(14)),              // Đã kết thúc 14 giờ trước
    status: "COMPLETED",
    winningBidId: null,
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(49)),
    updatedAt: new Date(now.getTime() - ms(14))
  },

  // ==========================================
  // CASE 8: ĐÃ HỦY PHIÊN ĐẤU GIÁ (CANCELLED)
  // ==========================================
  {
    _id: "seed-auc-08-cancelled",
    shipperId: SHIPPER_1,
    title: "7 Tấn Thức Ăn Chăn Nuôi Thủy Sản CP Profeed",
    goodsType: "Thức ăn gia súc & Thủy sản",
    weight: 7.0,
    volume: 16.0,
    goodsValue: NumberDecimal("160000000.00"),
    vehicleTypeRequired: "TRUCK_MEDIUM",
    vehicleSpecs: { length: 6.5, width: 2.2, height: 2.2 },
    origin: "Tiền Giang - KCN Mỹ Tho",
    destination: "Bình Định - Thị xã Hoài Nhơn",
    pickupLocation: {
      locationName: "Nhà Máy Thức Ăn Thủy Sản CP",
      province: "Tiền Giang",
      address: "Lô 12, KCN Mỹ Tho, Xã Trung An, TP. Mỹ Tho",
      contactName: "Nguyễn Văn Đức",
      contactPhone: "0907112244",
      earliestTime: new Date(now.getTime() - ms(12)),
      latestTime: new Date(now.getTime() - ms(6))
    },
    deliveryLocation: {
      locationName: "Đại Lý Thủy Sản Hoài Nhơn",
      province: "Bình Định",
      address: "Khu Phố 4, Phường Tam Quan, Thị xã Hoài Nhơn",
      contactName: "Huỳnh Quốc Thái",
      contactPhone: "0981223344",
      earliestTime: new Date(now.getTime() + ms(16)),
      latestTime: new Date(now.getTime() + ms(24))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("8500000.00"),
    priceStep: NumberDecimal("100000.00"),
    maxBids: 10,
    images: [],
    notes: "Xe tải trung thùng bạt có phủ bạt hai lớp chống ướt mưa.",
    isDepositRequired: false,
    depositAmount: null,
    participationFeeTier: "LEVEL_1",
    participationFeeAmount: NumberDecimal("20000.00"),
    creationFeeTier: "LEVEL_1",
    creationFeeAmount: NumberDecimal("50000.00"),
    creationIdempotencyKey: "seed-key-08",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-08",
    creationFeeTransactionId: "seed-tx-08",
    registrationStartTime: new Date(now.getTime() - ms(36)),
    registrationEndTime: new Date(now.getTime() - ms(24)),
    startTime: new Date(now.getTime() - ms(20)),
    endTime: new Date(now.getTime() - ms(8)),
    status: "CANCELLED",
    winningBidId: null,
    cancellationReason: "Chủ hàng dời ngày xuất xưởng do kho đại lý đang nâng cấp hệ thống silo trữ thức ăn.",
    fraudFlag: false,
    fraudReason: null,
    createdAt: new Date(now.getTime() - ms(37)),
    updatedAt: new Date(now.getTime() - ms(22))
  },

  // ==========================================
  // CASE 9: LÔ HÀNG ĐANG VẬN CHUYỂN TRÊN ĐƯỜNG (SHIPPING / IN_TRANSIT)
  // ==========================================
  {
    _id: "seed-auc-09-shipping-in-transit",
    shipperId: SHIPPER_1,
    title: "22 Tấn Gỗ Tự Nhiên & Nội Thất Gỗ Thành Phẩm Cao Cấp",
    goodsType: "Đồ gỗ & Nội thất cao cấp",
    weight: 22.0,
    volume: 55.0,
    goodsValue: NumberDecimal("780000000.00"),
    vehicleTypeRequired: "CONTAINER_TRACTOR",
    vehicleSpecs: { length: 13.5, width: 2.45, height: 2.6 },
    origin: "Bình Dương - KCN Tân Uyên",
    destination: "Quảng Ninh - TP. Hạ Long",
    pickupLocation: {
      locationName: "Xưởng Đồ Gỗ Mỹ Nghệ Tân Uyên",
      province: "Bình Dương",
      address: "Ấp 4, Xã Hội Nghĩa, Thị xã Tân Uyên",
      contactName: "Trần Đình Khang",
      contactPhone: "0903889911",
      earliestTime: new Date(now.getTime() - ms(18)),
      latestTime: new Date(now.getTime() - ms(12))
    },
    deliveryLocation: {
      locationName: "Showroom Nội Thất Bãi Cháy",
      province: "Quảng Ninh",
      address: "Đường Hạ Long, Phường Bãi Cháy, TP. Hạ Long",
      contactName: "Hoàng Văn Tuấn",
      contactPhone: "0919223388",
      earliestTime: new Date(now.getTime() + ms(20)),
      latestTime: new Date(now.getTime() + ms(30))
    },
    auctionType: "PUBLIC",
    maxPrice: NumberDecimal("29000000.00"),
    priceStep: NumberDecimal("300000.00"),
    maxBids: 20,
    images: [
      "https://images.unsplash.com/photo-1538688525198-9b88f6f53126?w=800&auto=format&fit=crop"
    ],
    notes: "Hàng nội thất sơn bóng dễ trầy xước, yêu cầu bọc màng PE và xốp giảm chấn cẩn thận.",
    isDepositRequired: true,
    depositAmount: NumberDecimal("1500000.00"),
    participationFeeTier: "LEVEL_3",
    participationFeeAmount: NumberDecimal("100000.00"),
    creationFeeTier: "LEVEL_3",
    creationFeeAmount: NumberDecimal("200000.00"),
    creationIdempotencyKey: "seed-key-09",
    creationFeeStatus: "SETTLED",
    creationFeeHoldId: "seed-hold-09",
    creationFeeTransactionId: "seed-tx-09",
    registrationStartTime: new Date(now.getTime() - ms(48)),
    registrationEndTime: new Date(now.getTime() - ms(30)),
    startTime: new Date(now.getTime() - ms(28)),
    endTime: new Date(now.getTime() - ms(18)),
    status: "COMPLETED",
    winningBidId: "seed-bid-09-01",
    cancellationReason: null,
    fraudFlag: false,
    fraudReason: null,
    // Enriched trip simulation
    tripId: "99999999-0000-0000-0000-000000000001",
    trip: {
      id: "99999999-0000-0000-0000-000000000001",
      status: "IN_TRANSIT",
      driverName: "Lái Xe Nguyễn Văn Tài",
      driverPhone: "0911223344",
      vehiclePlate: "51D-999.99"
    },
    createdAt: new Date(now.getTime() - ms(50)),
    updatedAt: new Date(now.getTime() - ms(10))
  }
];

// Duplicate auctions for Shipper 2 (Demo Shipper) so tests work on both accounts!
const shipper2Auctions = auctions.map((auc) => ({
  ...auc,
  _id: auc._id.replace("seed-auc-", "seed-auc2-"),
  shipperId: SHIPPER_2,
  title: "[Demo] " + auc.title,
  creationIdempotencyKey: auc.creationIdempotencyKey + "-shipper2"
}));

db.auctions.insertMany([...auctions, ...shipper2Auctions]);
print("=> Inserted auctions: " + (auctions.length + shipper2Auctions.length));

// ==========================================
// REGISTRATIONS SEED DATA
// ==========================================
const registrations = [
  // Case 2: 1 registration (Carrier 1)
  {
    _id: "seed-reg-02-01",
    auctionId: "seed-auc-02-phase1-registering",
    carrierId: CARRIER_1,
    vehicleId: VEHICLE_CARRIER_1_REF,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "LOCKED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("100000.00"),
    depositAmount: NumberDecimal("2000000.00"),
    depositHoldId: "seed-reg-hold-02-01",
    participationFeeTransactionId: "seed-reg-tx-02-01",
    idempotencyKey: "seed-reg-idem-02-01",
    createdAt: new Date(now.getTime() - ms(2)),
    updatedAt: new Date(now.getTime() - ms(2))
  },
  // Case 3: 2 registrations (Carrier 1 & Carrier 2)
  {
    _id: "seed-reg-03-01",
    auctionId: "seed-auc-03-phase2-waiting-auction",
    carrierId: CARRIER_1,
    vehicleId: VEHICLE_CARRIER_1_HEAVY,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "NOT_REQUIRED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("50000.00"),
    depositAmount: null,
    depositHoldId: null,
    participationFeeTransactionId: "seed-reg-tx-03-01",
    idempotencyKey: "seed-reg-idem-03-01",
    createdAt: new Date(now.getTime() - ms(6)),
    updatedAt: new Date(now.getTime() - ms(6))
  },
  {
    _id: "seed-reg-03-02",
    auctionId: "seed-auc-03-phase2-waiting-auction",
    carrierId: CARRIER_2,
    vehicleId: VEHICLE_CARRIER_2_HEAVY,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "NOT_REQUIRED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("50000.00"),
    depositAmount: null,
    depositHoldId: null,
    participationFeeTransactionId: "seed-reg-tx-03-02",
    idempotencyKey: "seed-reg-idem-03-02",
    createdAt: new Date(now.getTime() - ms(5)),
    updatedAt: new Date(now.getTime() - ms(5))
  },
  // Case 4: 2 registrations (Carrier 1 & Carrier 2)
  {
    _id: "seed-reg-04-01",
    auctionId: "seed-auc-04-phase3-bidding-active",
    carrierId: CARRIER_1,
    vehicleId: VEHICLE_CARRIER_1,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "LOCKED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("100000.00"),
    depositAmount: NumberDecimal("1500000.00"),
    depositHoldId: "seed-reg-hold-04-01",
    participationFeeTransactionId: "seed-reg-tx-04-01",
    idempotencyKey: "seed-reg-idem-04-01",
    createdAt: new Date(now.getTime() - ms(8)),
    updatedAt: new Date(now.getTime() - ms(8))
  },
  {
    _id: "seed-reg-04-02",
    auctionId: "seed-auc-04-phase3-bidding-active",
    carrierId: CARRIER_2,
    vehicleId: VEHICLE_CARRIER_2_TRACTOR,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "LOCKED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("100000.00"),
    depositAmount: NumberDecimal("1500000.00"),
    depositHoldId: "seed-reg-hold-04-02",
    participationFeeTransactionId: "seed-reg-tx-04-02",
    idempotencyKey: "seed-reg-idem-04-02",
    createdAt: new Date(now.getTime() - ms(7)),
    updatedAt: new Date(now.getTime() - ms(7))
  },
  // Case 5: 1 registration (Carrier 2)
  {
    _id: "seed-reg-05-01",
    auctionId: "seed-auc-05-phase3-bidding-no-bids",
    carrierId: CARRIER_2,
    vehicleId: VEHICLE_CARRIER_2_MED,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "NOT_REQUIRED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("50000.00"),
    depositAmount: null,
    depositHoldId: null,
    participationFeeTransactionId: "seed-reg-tx-05-01",
    idempotencyKey: "seed-reg-idem-05-01",
    createdAt: new Date(now.getTime() - ms(3)),
    updatedAt: new Date(now.getTime() - ms(3))
  },
  // Case 6: 2 registrations
  {
    _id: "seed-reg-06-01",
    auctionId: "seed-auc-06-phase4-closed-awarded",
    carrierId: CARRIER_1,
    vehicleId: VEHICLE_CARRIER_1_HEAVY,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "LOCKED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("100000.00"),
    depositAmount: NumberDecimal("2000000.00"),
    depositHoldId: "seed-reg-hold-06-01",
    participationFeeTransactionId: "seed-reg-tx-06-01",
    idempotencyKey: "seed-reg-idem-06-01",
    createdAt: new Date(now.getTime() - ms(20)),
    updatedAt: new Date(now.getTime() - ms(20))
  },
  {
    _id: "seed-reg-06-02",
    auctionId: "seed-auc-06-phase4-closed-awarded",
    carrierId: CARRIER_2,
    vehicleId: VEHICLE_CARRIER_2_HEAVY,
    status: "REGISTERED",
    paymentStatus: "COMPLETED",
    depositStatus: "LOCKED",
    participationFeeStatus: "PAID",
    participationFeeAmount: NumberDecimal("100000.00"),
    depositAmount: NumberDecimal("2000000.00"),
    depositHoldId: "seed-reg-hold-06-02",
    participationFeeTransactionId: "seed-reg-tx-06-02",
    idempotencyKey: "seed-reg-idem-06-02",
    createdAt: new Date(now.getTime() - ms(18)),
    updatedAt: new Date(now.getTime() - ms(18))
  }
];

db.auction_registrations.insertMany(registrations);
print("=> Inserted registrations: " + registrations.length);

// ==========================================
// BIDS SEED DATA
// ==========================================
const bids = [
  // Bids for Case 4 (Đang đấu giá sôi nổi)
  {
    _id: "seed-bid-04-01",
    auctionId: "seed-auc-04-phase3-bidding-active",
    carrierId: CARRIER_1,
    bidAmount: NumberDecimal("27500000.00"),
    bidTime: new Date(now.getTime() - min(35)),
    idempotencyKey: "seed-bid-key-04-01"
  },
  {
    _id: "seed-bid-04-02",
    auctionId: "seed-auc-04-phase3-bidding-active",
    carrierId: CARRIER_2,
    bidAmount: NumberDecimal("27000000.00"),
    bidTime: new Date(now.getTime() - min(25)),
    idempotencyKey: "seed-bid-key-04-02"
  },
  {
    _id: "seed-bid-04-03",
    auctionId: "seed-auc-04-phase3-bidding-active",
    carrierId: CARRIER_1,
    bidAmount: NumberDecimal("26600000.00"),
    bidTime: new Date(now.getTime() - min(15)),
    idempotencyKey: "seed-bid-key-04-03"
  },
  {
    _id: "seed-bid-04-04",
    auctionId: "seed-auc-04-phase3-bidding-active",
    carrierId: CARRIER_2,
    bidAmount: NumberDecimal("26200000.00"), // Lowest bid hiện tại!
    bidTime: new Date(now.getTime() - min(5)),
    idempotencyKey: "seed-bid-key-04-04"
  },

  // Bids for Case 6 (Đã đóng thầu - Awarded)
  {
    _id: "seed-bid-06-01",
    auctionId: "seed-auc-06-phase4-closed-awarded",
    carrierId: CARRIER_2,
    bidAmount: NumberDecimal("24000000.00"),
    bidTime: new Date(now.getTime() - ms(8)),
    idempotencyKey: "seed-bid-key-06-01"
  },
  {
    _id: "seed-bid-06-02",
    auctionId: "seed-auc-06-phase4-closed-awarded",
    carrierId: CARRIER_1,
    bidAmount: NumberDecimal("22800000.00"),
    bidTime: new Date(now.getTime() - ms(6)),
    idempotencyKey: "seed-bid-key-06-02"
  },
  {
    _id: "seed-bid-06-03",
    auctionId: "seed-auc-06-phase4-closed-awarded",
    carrierId: CARRIER_1,
    bidAmount: NumberDecimal("21500000.00"), // Winning bid!
    bidTime: new Date(now.getTime() - ms(4)),
    idempotencyKey: "seed-bid-key-06-03"
  },

  // Bid for Case 9 (Đang vận chuyển)
  {
    _id: "seed-bid-09-01",
    auctionId: "seed-auc-09-shipping-in-transit",
    carrierId: CARRIER_1,
    bidAmount: NumberDecimal("27000000.00"),
    bidTime: new Date(now.getTime() - ms(20)),
    idempotencyKey: "seed-bid-key-09-01"
  }
];

db.bids.insertMany(bids);
print("=> Inserted bids: " + bids.length);

print("=== SEEDING COMPLETED SUCCESSFULLY ===");
