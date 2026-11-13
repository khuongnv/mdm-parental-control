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
    [string]$ParseMode = "HTML"
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

if ([string]::IsNullOrWhiteSpace($finalMsg)) {
    Write-Warning "[Telegram] Khong co noi dung gui."
    exit 0
}

$url = "https://api.telegram.org/bot$BotToken/sendMessage"

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
    $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 10
    if ($response.ok) {
        Write-Host "[Telegram] Sent to HUB-LOG successfully: $($response.result.message_id)" -ForegroundColor Green
    } else {
        Write-Warning "[Telegram] API returned ok=false: $($response.description)"
    }
} catch {
    Write-Warning "[Telegram] Khong the gui tin nhan Telegram: $($_.Exception.Message)"
}
