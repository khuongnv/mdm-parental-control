param(
    [Parameter(Mandatory = $false)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [string]$StepTitle,

    [Parameter(Mandatory = $false)]
    [string]$ResultStatus = "Thanh cong",

    [Parameter(Mandatory = $false)]
    [string]$ChannelId = "-1003609918702",

    [Parameter(Mandatory = $false)]
    [string]$BotToken = "8005142785:AAHSrJ2Yp4l0Gj6Yk7iu8hwSwThZIiVKrCU",

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

$iconSuccess = [char]::ConvertFromUtf32(0x2705) # Checkmark
$iconWait    = [char]::ConvertFromUtf32(0x23F3) # Hourglass
$iconWarn    = [char]::ConvertFromUtf32(0x26A0) # Warning
$iconNote    = [char]::ConvertFromUtf32(0x1F4DD) # Memo
$iconChart   = [char]::ConvertFromUtf32(0x1F4CA) # Bar chart
$iconClock   = [char]::ConvertFromUtf32(0x23F1) # Stopwatch
$iconPhone   = [char]::ConvertFromUtf32(0x1F4F1) # Mobile Phone

$nowStr = (Get-Date).ToString("HH:mm:ss dd/MM/yyyy")

$finalMsg = ""
if (-not [string]::IsNullOrWhiteSpace($StepTitle)) {
    $statusIcon = if ($ResultStatus -match "Thanh cong|HOAN TAT|Thành công|HOÀN TẤT|Thành Công") { $iconSuccess } elseif ($ResultStatus -match "Dang|Cho|Tien hanh|Đang|Chờ|Tiến hành") { $iconWait } else { $iconWarn }
    $finalMsg = "$statusIcon <b>[VFAM CI/CD BUILD] $StepTitle</b>`n`n"
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $finalMsg += "$iconNote <b>Noi dung:</b> $Message`n"
    }
    $finalMsg += "$iconChart <b>Ket qua:</b> $ResultStatus`n"
    $finalMsg += "$iconClock <i>$nowStr</i>"
} else {
    $finalMsg = $Message
}

if ([string]::IsNullOrWhiteSpace($finalMsg) -and [string]::IsNullOrWhiteSpace($QrCodeData) -and [string]::IsNullOrWhiteSpace($PhotoUrl) -and [string]::IsNullOrWhiteSpace($PhotoPath)) {
    Write-Warning "[Telegram] Khong co noi dung hoac anh can gui."
    exit 0
}

# Xử lý tạo link ảnh QR Code nếu có QrCodeData
if (-not [string]::IsNullOrWhiteSpace($QrCodeData) -and [string]::IsNullOrWhiteSpace($PhotoUrl) -and [string]::IsNullOrWhiteSpace($PhotoPath)) {
    $escapedData = [System.Uri]::EscapeDataString($QrCodeData)
    $PhotoUrl = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&margin=12&data=$escapedData"
}

# 1. TRƯỜNG HỢP GỬI ẢNH (sendPhoto)
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
            $caption = "$iconPhone <b>[QR CODE CAI DAT] $StepTitle</b>`n<i>Quet ma QR bang Camera de cai dat ung dung ngay lap tuc.</i>"
            $sendSeparateText = $true
        }
    }

    # A. Gửi từ PhotoUrl trực tuyến (VD: api.qrserver.com)
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
                Write-Host "[Telegram] Sent Photo/QR to HUB-LOG successfully: $($response.result.message_id)" -ForegroundColor Green
                $photoSent = $true
            }
        } catch {
            Write-Warning "[Telegram] sendPhoto qua URL that bai: $($_.Exception.Message)"
        }
    }

    # B. Gửi từ file ảnh cục bộ (PhotoPath) qua curl.exe nếu PhotoUrl chưa gửi thành công hoặc PhotoPath được chỉ định
    if (-not $photoSent -and -not [string]::IsNullOrWhiteSpace($PhotoPath) -and (Test-Path $PhotoPath)) {
        try {
            $curlExe = if (Get-Command curl.exe -ErrorAction SilentlyContinue) { "curl.exe" } else { "curl" }
            $curlArgs = @("-s", "-X", "POST", $photoEndpoint, "-F", "chat_id=$ChannelId", "-F", "photo=@$PhotoPath")
            if (-not [string]::IsNullOrWhiteSpace($caption)) {
                $curlArgs += @("-F", "caption=$caption", "-F", "parse_mode=$ParseMode")
            }
            $curlOut = & $curlExe @curlArgs | Out-String
            if ($curlOut -match '"ok":\s*true') {
                Write-Host "[Telegram] Sent local Photo/QR via curl successfully." -ForegroundColor Green
                $photoSent = $true
            } else {
                Write-Warning "[Telegram] curl sendPhoto failed: $curlOut"
            }
        } catch {
            Write-Warning "[Telegram] sendPhoto qua curl that bai: $($_.Exception.Message)"
        }
    }

    # Nếu ảnh đã gửi kèm toàn bộ nội dung trong caption, kết thúc tại đây
    if ($photoSent -and -not $sendSeparateText) {
        exit 0
    }
}

# 2. TRƯỜNG HỢP GỬI TIN NHẮN VĂN BẢN (sendMessage)
# Chạy khi không có ảnh, hoặc khi caption ảnh quá dài cần gửi bài viết chi tiết riêng
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
            Write-Host "[Telegram] Sent message to HUB-LOG successfully: $($response.result.message_id)" -ForegroundColor Green
        } else {
            Write-Warning "[Telegram] API returned ok=false: $($response.description)"
        }
    } catch {
        Write-Warning "[Telegram] Khong the gui tin nhan Telegram: $($_.Exception.Message)"
    }
}
