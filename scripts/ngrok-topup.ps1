# ngrok-topup.ps1
# Khoi tao ngrok tunnel cho luong nap tien SePay (IPN).

$ErrorActionPreference = "Stop"

function Write-Section($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

$ngrokCmd = Get-Command ngrok -ErrorAction SilentlyContinue
if (-not $ngrokCmd) {
    Write-Host "[LOI] Khong tim thay ngrok trong PATH." -ForegroundColor Red
    exit 1
}

try {
    $health = Invoke-WebRequest -Uri "http://localhost:8080/actuator/health" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    Write-Section "Gateway :8080 san sang ($($health.StatusCode))"
} catch {
    Write-Host "[CANH BAO] Gateway :8080 chua phan hoi healthcheck." -ForegroundColor Yellow
}
# Mo tunnel background
Write-Section "Khoi dong ngrok http 8080"
$existing = Get-Process ngrok -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "      Phat hien ngrok dang chay - giu nguyen."
} else {
    Start-Process -FilePath "ngrok" -ArgumentList "http","8080","--log=stdout" -WindowStyle Hidden
    Start-Sleep -Seconds 3
}
# Lay public URL tu ngrok API
$publicUrl = $null
for ($i = 0; $i -lt 10; $i++) {
    try {
        $tunnels = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 3
        $tunnel = $tunnels.tunnels | Where-Object { $_.config.addr -match "8080" -and $_.public_url -like "https://*" } | Select-Object -First 1
        if ($tunnel) { $publicUrl = $tunnel.public_url; break }
    } catch { Start-Sleep -Seconds 1 }
}

if (-not $publicUrl) {
    Write-Host "[LOI] Khong lay duoc public URL tu ngrok API (127.0.0.1:4040)." -ForegroundColor Red
    Write-Host "      Mo 'ngrok http 8080' bang tay va copy URL trong terminal ngrok."
    exit 1
}
# Doc IPN secret tu .env (fallback sang SEPAY_SECRET_KEY)
$envFile = Join-Path $PSScriptRoot "..\.env"
$ipnSecret = ""
$secretKey = ""
if (Test-Path $envFile) {
    $lines = Get-Content $envFile
    foreach ($line in $lines) {
        if ($line -match "^\s*SEPAY_IPN_SECRET\s*=\s*(.+)\s*$") { $ipnSecret = $Matches[1] }
        if ($line -match "^\s*SEPAY_SECRET_KEY\s*=\s*(.+)\s*$") { $secretKey = $Matches[1] }
    }
}
if (-not $ipnSecret) { $ipnSecret = $secretKey }
if (-not $ipnSecret) { $ipnSecret = "<SEPAY_IPN_SECRET trong .env>" }

Write-Section "Thanh cong - cau hinh SePay sandbox nhu sau"
Write-Host ""
Write-Host ("  Public URL : {0}" -f $publicUrl) -ForegroundColor Green
Write-Host ("  IPN URL    : {0}/api/v1/payments/sepay/ipn" -f $publicUrl) -ForegroundColor Green
Write-Host ("  Secret Key : {0}" -f $ipnSecret) -ForegroundColor Green
Write-Host ""
Write-Host "  Dang ky IPN URL + Secret Key tai trang quan tri merchant SePay sandbox."
Write-Host "  Chi tiet: docs/002-sepay-topup-ngrok.md"
Write-Host "  Dashboard ngrok: http://127.0.0.1:4040"
Write-Host ""