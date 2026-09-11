fetch('http://localhost:8080/api/v1/empty-routes', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    truckId: '29C-12345',
    companyId: '55555555-5555-5555-5555-555555550000',
    expectedEmptyTime: '2026-08-30T10:00:00',
    origin: 'Thái Nguyên',
    destination: 'Hải Phòng',
    latitude: 21.0,
    longitude: 105.8
  })
}).then(async res => console.log(res.status, await res.text())).catch(console.error);
