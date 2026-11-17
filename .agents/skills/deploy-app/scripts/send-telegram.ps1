param(
    [Parameter(Mandatory = $false)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [string]$StepTitle,

    [Parameter(Mandatory = $false)]
    [string]$ResultStatus = "Thành công",

    [Parameter(Mandatory = $false)]
    [string]$ChannelId = "",

    [Parameter(Mandatory = $false)]
    [string]$BotToken = "",

    [Parameter(Mandatory = $false)]
    [string]$ParseMode = "HTML",

    [Parameter(Mandatory = $false)]
    [string]$QrCodeData,

    [Parameter(Mandatory = $false)]
    [string]$PhotoUrl,

    [Parameter(Mandatory = $false)]
    [string]$PhotoPath
)

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# Tự động nạp cấu hình từ .env tại repo root nếu có
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$envFile = Join-Path $repoRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$" } | ForEach-Object {
        $varName = $matches[1]
        $varVal = $matches[2].Trim('"', "'", " ")
        if (-not [Environment]::GetEnvironmentVariable($varName)) {
            [Environment]::SetEnvironmentVariable($varName, $varVal, "Process")
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ChannelId)) {
    $ChannelId = if ($env:TELEGRAM_CHANNEL_ID) { $env:TELEGRAM_CHANNEL_ID } else { "" }
}
if ([string]::IsNullOrWhiteSpace($BotToken)) {
    $BotToken = if ($env:TELEGRAM_BOT_TOKEN) { $env:TELEGRAM_BOT_TOKEN } else { "" }
}

if ([string]::IsNullOrWhiteSpace($BotToken) -or [string]::IsNullOrWhiteSpace($ChannelId)) {
    Write-Warning "[Telegram] TELEGRAM_BOT_TOKEN hoặc TELEGRAM_CHANNEL_ID chưa được cấu hình. Bỏ qua thông báo Telegram."
    exit 0
}

$iconRocket  = [char]::ConvertFromUtf32(0x1F680) # 🚀 Rocket
$iconSuccess = [char]::ConvertFromUtf32(0x2705)  # ✅ Checkmark
$iconWait    = [char]::ConvertFromUtf32(0x23F3)  # ⏳ Hourglass
$iconWarn    = [char]::ConvertFromUtf32(0x26A0)  # ⚠️ Warning
$iconNote    = [char]::ConvertFromUtf32(0x1F4DD)  # 📝 Memo
$iconChart   = [char]::ConvertFromUtf32(0x1F4CA)  # 📊 Bar chart
$iconClock   = [char]::ConvertFromUtf32(0x23F1)  # ⏱️ Stopwatch
$iconPhone   = [char]::ConvertFromUtf32(0x1F4F1)  # 📱 Mobile Phone

$nowStr = (Get-Date).ToString("HH:mm:ss dd/MM/yyyy")

$finalMsg = ""
if (-not [string]::IsNullOrWhiteSpace($StepTitle)) {
    $isComplete = ($ResultStatus -match "Thành công|HOÀN TẤT|Hoàn tất|Thanh cong|HOAN TAT|Success") -or ($StepTitle -match "THÀNH CÔNG|HOÀN TẤT|TỔNG KẾT|Tong ket")
    $statusIcon = if ($isComplete) { $iconRocket } elseif ($ResultStatus -match "Đang|Chờ|Tiến hành|Dang|Cho|Tien hanh") { $iconWait } else { $iconWarn }
    
    if ($isComplete -and ($StepTitle -match "TỔNG KẾT|THÀNH CÔNG|HOÀN TẤT")) {
        $finalMsg = "$statusIcon <b>[VFAM CI/CD] $StepTitle</b>`n`n"
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $finalMsg += "$Message`n`n"
        }
        $finalMsg += "$iconClock <i>$nowStr</i>"
    } else {
        $finalMsg = "$statusIcon <b>[VFAM CI/CD] $StepTitle</b>`n`n"
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $finalMsg += "$iconNote <b>Chi tiết:</b> $Message`n"
        }
        $finalMsg += "$iconChart <b>Trạng thái:</b> $ResultStatus`n"
        $finalMsg += "$iconClock <i>$nowStr</i>"
    }
} else {
    $finalMsg = $Message
}

if ([string]::IsNullOrWhiteSpace($finalMsg) -and [string]::IsNullOrWhiteSpace($QrCodeData) -and [string]::IsNullOrWhiteSpace($PhotoUrl) -and [string]::IsNullOrWhiteSpace($PhotoPath)) {
    Write-Warning "[Telegram] Không có nội dung hoặc ảnh cần gửi."
    exit 0
}

# Tự động tạo link ảnh QR Code nếu có QrCodeData
if (-not [string]::IsNullOrWhiteSpace($QrCodeData) -and [string]::IsNullOrWhiteSpace($PhotoUrl)) {
    $escapedData = [System.Uri]::EscapeDataString($QrCodeData)
    $PhotoUrl = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&margin=12&data=$escapedData"
}

# 1. TRƯỜNG HỢP GỬI ẢNH (sendPhoto) - Kết hợp ảnh QR Code và toàn bộ thông báo trong 1 tin gọn gàng
$photoSent = $false
if (-not [string]::IsNullOrWhiteSpace($PhotoUrl) -or (-not [string]::IsNullOrWhiteSpace($PhotoPath) -and (Test-Path $PhotoPath))) {
    $photoEndpoint = "https://api.telegram.org/bot$BotToken/sendPhoto"
    
    # Kiểm tra độ dài caption của Telegram (tối đa 1024 ký tự)
    $caption = ""
    $sendSeparateText = $false
    if (-not [string]::IsNullOrWhiteSpace($finalMsg)) {
        if ($finalMsg.Length -le 1024) {
            $caption = $finalMsg
        } else {
            $caption = "$iconPhone <b>[MÃ QR CÀI ĐẶT] $StepTitle</b>`n<i>Quét mã QR bằng Camera để cài đặt ngay.</i>"
            $sendSeparateText = $true
        }
    }

    # A. Ưu tiên gửi từ PhotoUrl (Telegram tải trực tiếp từ URL, hỗ trợ UTF-8 chuẩn 100%)
    if (-not [string]::IsNullOrWhiteSpace($PhotoUrl)) {
        try {
            $photoPayload = @{
                chat_id = $ChannelId
                photo = $PhotoUrl
            }
            if (-not [string]::IsNullOrWhiteSpace($caption)) {
                $photoPayload["caption"] = $caption
                if ($ParseMode) { $photoPayload["parse_mode"] = $ParseMode }
            }

            $json = $photoPayload | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response = Invoke-RestMethod -Uri $photoEndpoint -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 15
            if ($response.ok) {
                Write-Host "[Telegram] Đã gửi ảnh QR Code & thông báo tổng kết tới HUB-LOG: $($response.result.message_id)" -ForegroundColor Green
                $photoSent = $true
            }
        } catch {
            Write-Warning "[Telegram] sendPhoto qua PhotoUrl lỗi: $($_.Exception.Message)"
        }
    }

    # B. Gửi từ file ảnh cục bộ (PhotoPath) nếu PhotoUrl không khả dụng
    if (-not $photoSent -and -not [string]::IsNullOrWhiteSpace($PhotoPath) -and (Test-Path $PhotoPath)) {
        try {
            $curlExe = if (Get-Command curl.exe -ErrorAction SilentlyContinue) { "curl.exe" } else { "curl" }
            # Lưu caption ra file tạm UTF-8 để curl đọc an toàn
            $captionTmp = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllText($captionTmp, $caption, [System.Text.Encoding]::UTF8)

            $curlArgs = @("-s", "-X", "POST", $photoEndpoint, "-F", "chat_id=$ChannelId", "-F", "photo=@$PhotoPath", "-F", "caption=<$captionTmp", "-F", "parse_mode=$ParseMode")
            $curlOut = & $curlExe @curlArgs | Out-String
            Remove-Item $captionTmp -Force -ErrorAction SilentlyContinue

            if ($curlOut -match '"ok":\s*true') {
                Write-Host "[Telegram] Đã gửi file ảnh QR Code qua curl thành công." -ForegroundColor Green
                $photoSent = $true
            } else {
                Write-Warning "[Telegram] curl sendPhoto failed: $curlOut"
            }
        } catch {
            Write-Warning "[Telegram] sendPhoto qua curl lỗi: $($_.Exception.Message)"
        }
    }

    # Nếu ảnh đã gửi kèm toàn bộ thông báo trong caption, kết thúc luôn (không spam tin thứ 2)
    if ($photoSent -and -not $sendSeparateText) {
        exit 0
    }
}

# 2. TRƯỜNG HỢP GỬI TIN NHẮN VĂN BẢN (sendMessage) - Dành cho các bước tiến trình trung gian
if (-not [string]::IsNullOrWhiteSpace($finalMsg)) {
    $msgEndpoint = "https://api.telegram.org/bot$BotToken/sendMessage"
    $payload = @{
        chat_id = $ChannelId
        text = $finalMsg
    }
    if ($ParseMode) {
        $payload["parse_mode"] = $ParseMode
    }

    try {
        $json = $payload | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response = Invoke-RestMethod -Uri $msgEndpoint -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 10
        if ($response.ok) {
            Write-Host "[Telegram] Đã gửi thông báo tiến trình tới HUB-LOG: $($response.result.message_id)" -ForegroundColor Green
        } else {
            Write-Warning "[Telegram] API returned ok=false: $($response.description)"
        }
    } catch {
        Write-Warning "[Telegram] Không thể gửi tin nhắn Telegram: $($_.Exception.Message)"
    }
}
