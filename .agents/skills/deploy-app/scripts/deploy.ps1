<#
.SYNOPSIS
    Kịch bản tự động hóa điều phối build, đóng gói và phát hành ứng dụng đa nền tảng (Android & iOS).
.DESCRIPTION
    Hỗ trợ phát hành:
    - Child DO Agent (Android): vfam-child-android-v<X.Y.Z>
    - Parent Admin (Android): vfam-admin-android-v<X.Y.Z>
    - Parent Admin (iOS Enterprise): admin-ios-v<X.Y.Z>
    - Toàn bộ hệ thống: -Target all -Platform all
    Tích hợp tự động hóa:
    - Đóng gói APK / IPA
    - Tạo mã QR Code cài đặt
    - Đẩy GitHub Releases
    - Giám sát Telegram HUB-LOG thời gian thực
#>
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("target", "child", "admin", "all")]
    [string]$Target = "admin",

    [Parameter(Mandatory=$false)]
    [ValidateSet("android", "ios", "all")]
    [string]$Platform = "android",

    [Parameter(Mandatory=$false)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$Notes = "Bản phát hành ứng dụng hệ thống MDM Parental Control.",

    [Parameter(Mandatory=$false)]
    [string]$ChannelId = "",

    [Parameter(Mandatory=$false)]
    [string]$BotToken = ""
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
Set-Location $repoRoot

# Tự động nạp cấu hình từ .env tại repo root nếu có
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

if ([string]::IsNullOrWhiteSpace($Version)) {
    $adminPubspecPath = Join-Path $repoRoot "admin-node\pubspec.yaml"
    if (Test-Path $adminPubspecPath) {
        $content = Get-Content -Path $adminPubspecPath -Raw -Encoding UTF8
        if ($content -match "version:\s*([0-9\.]+)") {
            $Version = $matches[1].Trim()
        } else {
            $Version = "1.5.4"
        }
    } else {
        $Version = "1.5.4"
    }
}

$telegramScript = Join-Path $PSScriptRoot "send-telegram.ps1"
function Send-TgStep {
    param([string]$Title, [string]$Message, [string]$Status = "Thành công", [string]$QrCodeData, [string]$PhotoPath)
    if (Test-Path $telegramScript) {
        $tgParams = @{
            StepTitle = $Title
            Message = $Message
            ResultStatus = $Status
        }
        if (-not [string]::IsNullOrWhiteSpace($ChannelId)) {
            $tgParams["ChannelId"] = $ChannelId
        }
        if (-not [string]::IsNullOrWhiteSpace($BotToken)) {
            $tgParams["BotToken"] = $BotToken
        }
        if (-not [string]::IsNullOrWhiteSpace($QrCodeData)) {
            $tgParams["QrCodeData"] = $QrCodeData
        }
        if (-not [string]::IsNullOrWhiteSpace($PhotoPath)) {
            $tgParams["PhotoPath"] = $PhotoPath
        }
        & $telegramScript @tgParams
    }
}

# Nếu yêu cầu phát hành iOS riêng cho Admin Node: Điều hướng sang deploy_ios.ps1
if ($Platform -eq "ios") {
    $iosScript = Join-Path $PSScriptRoot "deploy_ios.ps1"
    & $iosScript -Version $Version -Notes $Notes -ChannelId $ChannelId -BotToken $BotToken
    exit $LASTEXITCODE
}

# Nếu yêu cầu phát hành toàn bộ (all): Tuần tự phát hành Child Android, Admin Android, Admin iOS và Unified Release (Latest)
if ($Target -eq "all") {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "KHỞI ĐỘNG PHÁT HÀNH TOÀN BỘ HỆ THỐNG (ALL)" -ForegroundColor Cyan
    Write-Host "Version: $Version" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    Write-Host ">>> 1/4: PHÁT HÀNH CHILD DO AGENT (ANDROID)..." -ForegroundColor Yellow
    & $PSCommandPath -Target child -Platform android -Version $Version -Notes $Notes -ChannelId $ChannelId -BotToken $BotToken
    if ($LASTEXITCODE -ne 0) { throw "Phát hành Child Android thất bại với exit code $LASTEXITCODE" }

    Write-Host ">>> 2/4: PHÁT HÀNH PARENT ADMIN (ANDROID)..." -ForegroundColor Yellow
    & $PSCommandPath -Target admin -Platform android -Version $Version -Notes $Notes -ChannelId $ChannelId -BotToken $BotToken
    if ($LASTEXITCODE -ne 0) { throw "Phát hành Admin Android thất bại với exit code $LASTEXITCODE" }

    if ($Platform -eq "all" -or $Platform -eq "ios") {
        Write-Host ">>> 3/4: PHÁT HÀNH PARENT ADMIN (IOS ENTERPRISE)..." -ForegroundColor Yellow
        $iosScript = Join-Path $PSScriptRoot "deploy_ios.ps1"
        & $iosScript -Version $Version -Notes $Notes -ChannelId $ChannelId -BotToken $BotToken
        if ($LASTEXITCODE -ne 0) { throw "Phát hành Admin iOS thất bại với exit code $LASTEXITCODE" }
    }

    Write-Host ">>> 4/4: PHÁT HÀNH UNIFIED GITHUB RELEASE v$Version (--latest)..." -ForegroundColor Yellow
    $unifiedTag = "v$Version"
    $unifiedTitle = "VFam MDM Parental Control Suite v$Version (Android Child DO, Admin Android & iOS Enterprise)"
    git tag -a $unifiedTag -m "$unifiedTitle" -f
    git push origin $unifiedTag -f

    if (-not $env:GH_TOKEN -and -not $env:GITHUB_TOKEN) {
        try {
            $credOut = ("protocol=https`nhost=github.com`n`n" | git credential fill | Out-String)
            if ($credOut -match "password=(.+)") {
                $env:GH_TOKEN = $matches[1].Trim()
            }
        } catch {}
    }

    $ghExe = if (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } elseif (Test-Path "C:\Program Files\GitHub CLI\gh.exe") { "C:\Program Files\GitHub CLI\gh.exe" } else { $null }
    if ($ghExe) {
        $releaseDir = Join-Path $repoRoot "release"
        $unifiedAssets = @()
        $candidates = @(
            "vfam-child-android-$Version.apk",
            "vfam-admin-android-$Version.apk",
            "vfam-admin-ios-$Version.ipa",
            "manifest.plist"
        )
        foreach ($c in $candidates) {
            $p = Join-Path $releaseDir $c
            if (Test-Path $p) { $unifiedAssets += "`"$p`"" }
        }
        & "$ghExe" release delete $unifiedTag --yes 2>$null
        $uCmd = "& `"$ghExe`" release create $unifiedTag $($unifiedAssets -join ' ') --title `"$unifiedTitle`" --notes `"$Notes`" --verify-tag --latest"
        Invoke-Expression $uCmd
        Write-Host "Unified GitHub Release $unifiedTag (--latest) đã tạo thành công!" -ForegroundColor Green
    }

    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "HOÀN TẤT PHÁT HÀNH TOÀN BỘ HỆ THỐNG PHIÊN BẢN v$Version!" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    exit 0
}

# Xác định chuẩn hóa Target
$normTarget = if ($Target -eq "target" -or $Target -eq "child") { "child" } else { "admin" }

# Xác định tag chuẩn phân biệt nền tảng và app
$tag = "$normTarget-$Platform-v$Version"

$releaseTitle = if ($normTarget -eq "child") {
    "VFam Child Agent (Android) Release v$Version"
} else {
    "VFam Parent Admin (Android) Release v$Version"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "KHỞI ĐỘNG CI/CD BUILD & DEPLOY ANDROID" -ForegroundColor Cyan
Write-Host "Target: $normTarget | Platform: $Platform | Tag: $tag | Version: $Version" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Send-TgStep -Title "Khởi động phát hành Android ($normTarget)" `
    -Message "Mục tiêu: <b>$normTarget</b> | Nền tảng: <b>$Platform</b>`nPhiên bản: <b>v$Version</b> (Git Tag: <code>$tag</code>)" `
    -Status "Đang chuẩn bị môi trường..."

$artifacts = @()
$releaseDir = Join-Path $repoRoot "release"
if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Force $releaseDir | Out-Null
}

# 1. BUILD TARGET NODE (CHILD ANDROID)
if ($normTarget -eq "child" -or $normTarget -eq "all") {
    Send-TgStep -Title "Biên dịch Target Node (Child DO Agent)" `
        -Message "Đang đồng bộ version $Version và chạy gradle assembleDebug..." `
        -Status "Đang biên dịch..."

    Write-Host "Đồng bộ version Target Node lên $Version..." -ForegroundColor Cyan
    $targetGradlePath = Join-Path $repoRoot "target-node\app\build.gradle.kts"
    if (Test-Path $targetGradlePath) {
        $gradleContent = Get-Content -Path $targetGradlePath -Raw -Encoding UTF8
        $oldVerName = if ($gradleContent -match 'versionName\s*=\s*"([^"]+)"') { $matches[1] } else { "" }
        if ($gradleContent -match 'versionCode\s*=\s*(\d+)') {
            $curCode = [int]$matches[1]
            $newCode = if ($oldVerName -ne $Version) { $curCode + 1 } else { $curCode }
            $gradleContent = $gradleContent -replace 'versionCode\s*=\s*\d+', "versionCode = $newCode"
        }
        $gradleContent = $gradleContent -replace 'versionName\s*=\s*"[^"]+"', "versionName = `"$Version`""
        Set-Content -Path $targetGradlePath -Value $gradleContent -Encoding UTF8 -NoNewline
    }

    Write-Host "Biên dịch Target Node (VFam Child)..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "target-node")
    Remove-Item -Path (Join-Path $repoRoot "target-node\app\build\outputs\apk\debug\app-debug.apk") -Force -ErrorAction SilentlyContinue

    .\gradlew.bat assembleDebug
    if ($LASTEXITCODE -ne 0) {
        Send-TgStep -Title "Biên dịch Target Node" -Message "Gradle build thất bại với exit code $LASTEXITCODE" -Status "Lỗi ❌"
        throw "Target Node build failed with exit code $LASTEXITCODE"
    }
    
    $targetApkPath = Join-Path $repoRoot "target-node\app\build\outputs\apk\debug\app-debug.apk"
    if (Test-Path $targetApkPath) {
        $destTargetApk = Join-Path $releaseDir "vfam-child-android-$Version.apk"
        Copy-Item -Path $targetApkPath -Destination $destTargetApk -Force
        $artifacts += $destTargetApk
        $childSize = [math]::Round((Get-Item $destTargetApk).Length / 1MB, 2)
        Write-Host "Target Node APK đã sẵn sàng: $destTargetApk ($childSize MB)" -ForegroundColor Green
        Send-TgStep -Title "Biên dịch Target Node hoàn tất" -Message "Đã xuất file APK: <code>vfam-child-android-$Version.apk</code> ($childSize MB)" -Status "Thành công"
    } else {
        throw "Không tìm thấy file APK của Target Node!"
    }
}

# 2. BUILD ADMIN NODE (PARENT FLUTTER ANDROID)
if ($normTarget -eq "admin" -or $normTarget -eq "all") {
    Send-TgStep -Title "Biên dịch Admin Node (Parent Flutter Android)" `
        -Message "Đang cập nhật pubspec.yaml và chạy flutter build apk --release..." `
        -Status "Đang biên dịch..."

    Write-Host "Đồng bộ version Admin Node lên $Version..." -ForegroundColor Cyan
    $adminBuildNumber = 13
    $adminPubspecPath = Join-Path $repoRoot "admin-node\pubspec.yaml"
    if (Test-Path $adminPubspecPath) {
        $pubContent = Get-Content -Path $adminPubspecPath -Raw -Encoding UTF8
        if ($pubContent -match 'version:\s*([0-9\.]+)\+(\d+)') {
            $oldPubVer = $matches[1]
            $curBuildNum = [int]$matches[2]
            $adminBuildNumber = if ($oldPubVer -ne $Version) { $curBuildNum + 1 } else { $curBuildNum }
        }
        $pubContent = $pubContent -replace 'version:\s*[0-9\.\+\-]+', "version: $Version+$adminBuildNumber"
        Set-Content -Path $adminPubspecPath -Value $pubContent -Encoding UTF8 -NoNewline
    }

    $adminUpdaterPath = Join-Path $repoRoot "admin-node\lib\services\github_release_updater.dart"
    if (Test-Path $adminUpdaterPath) {
        $uContent = Get-Content -Path $adminUpdaterPath -Raw -Encoding UTF8
        $uContent = $uContent -replace "defaultValue:\s*'[^']+'", "defaultValue: '$Version'"
        Set-Content -Path $adminUpdaterPath -Value $uContent -Encoding UTF8 -NoNewline
    }

    $adminIosAppDelegate = Join-Path $repoRoot "admin-node\ios\Runner\AppDelegate.swift"
    if (Test-Path $adminIosAppDelegate) {
        $sContent = Get-Content -Path $adminIosAppDelegate -Raw -Encoding UTF8
        $sContent = $sContent -replace 'CFBundleShortVersionString"\] as\? String \?\? "[^"]+"', "CFBundleShortVersionString`"] as? String ?? `"$Version`""
        $sContent = $sContent -replace 'CFBundleVersion"\] as\? String \?\? "[^"]+"', "CFBundleVersion`"] as? String ?? `"$adminBuildNumber`""
        Set-Content -Path $adminIosAppDelegate -Value $sContent -Encoding UTF8 -NoNewline
    }

    Write-Host "Biên dịch Admin Node (VFam Admin Android v$Version+$adminBuildNumber)..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "admin-node")
    Remove-Item -Path (Join-Path $repoRoot "admin-node\build\app\outputs\flutter-apk\app-release.apk") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $repoRoot "admin-node\build\app\outputs\apk\release\app-release.apk") -Force -ErrorAction SilentlyContinue

    $flutterArgs = @(
        "build", "apk", "--release",
        "--build-name=$Version",
        "--build-number=$adminBuildNumber",
        "--dart-define=APP_VERSION=$Version"
    )
    if ($env:SUPABASE_URL) {
        $flutterArgs += "--dart-define=SUPABASE_URL=$($env:SUPABASE_URL)"
    }
    if ($env:SUPABASE_ANON_KEY) {
        $flutterArgs += "--dart-define=SUPABASE_ANON_KEY=$($env:SUPABASE_ANON_KEY)"
    }

    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        Send-TgStep -Title "Biên dịch Admin Node" -Message "Flutter build apk thất bại với exit code $LASTEXITCODE" -Status "Lỗi ❌"
        throw "flutter build apk --release failed with exit code $LASTEXITCODE"
    }
    
    $adminApkPath = Join-Path $repoRoot "admin-node\build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $adminApkPath)) {
        $adminApkPath = Join-Path $repoRoot "admin-node\build\app\outputs\apk\release\app-release.apk"
    }
    if (Test-Path $adminApkPath) {
        $destAdminApk = Join-Path $releaseDir "vfam-admin-android-$Version.apk"
        Copy-Item -Path $adminApkPath -Destination $destAdminApk -Force
        $artifacts += $destAdminApk
        $adminSize = [math]::Round((Get-Item $destAdminApk).Length / 1MB, 2)
        Write-Host "Admin Node APK đã sẵn sàng: $destAdminApk ($adminSize MB)" -ForegroundColor Green
        Send-TgStep -Title "Biên dịch Admin Node hoàn tất" -Message "Đã xuất file APK: <code>vfam-admin-android-$Version.apk</code> ($adminSize MB)" -Status "Thành công"
    } else {
        throw "Không tìm thấy file APK của Admin Node!"
    }
}

Set-Location $repoRoot

# 3. GIT COMMIT & TAG
$status = git status --porcelain
if ($status) {
    git add .
    git commit -m "chore(release): bump version to $tag"
    git push origin main
}

Write-Host "Tạo git tag $tag..." -ForegroundColor Cyan
git tag -a $tag -m "$releaseTitle" -f
git push origin $tag -f

# 4. GITHUB RELEASE & QR CODE
if (-not $env:GH_TOKEN -and -not $env:GITHUB_TOKEN) {
    try {
        $credOut = ("protocol=https`nhost=github.com`n`n" | git credential fill | Out-String)
        if ($credOut -match "password=(.+)") {
            $env:GH_TOKEN = $matches[1].Trim()
        }
    } catch {}
}

$ghExe = if (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } elseif (Test-Path "C:\Program Files\GitHub CLI\gh.exe") { "C:\Program Files\GitHub CLI\gh.exe" } else { $null }

if ($ghExe) {
    Write-Host "Phát hành GitHub Release qua gh CLI..." -ForegroundColor Cyan
    $ghUrl = "https://github.com/khuongnv/mdm-parental-control/releases/tag/$tag"
    $primaryDownloadUrl = if ($artifacts.Count -gt 0) {
        $firstLeaf = Split-Path $artifacts[0] -Leaf
        "https://github.com/khuongnv/mdm-parental-control/releases/download/$tag/$firstLeaf"
    } else {
        $ghUrl
    }

    # Tạo file ảnh QR Code cục bộ
    $qrDestPath = Join-Path $releaseDir "$tag-qr.png"
    try {
        $escapedDl = [System.Uri]::EscapeDataString($primaryDownloadUrl)
        $qrApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&margin=12&data=$escapedDl"
        Invoke-WebRequest -Uri $qrApiUrl -OutFile $qrDestPath -TimeoutSec 10 -ErrorAction SilentlyContinue
        if (Test-Path $qrDestPath) { $artifacts += $qrDestPath }
    } catch {}

    $artifactArgs = $artifacts | ForEach-Object { "`"$_`"" }
    & "$ghExe" release delete $tag --yes 2>$null
    $cmd = "& `"$ghExe`" release create $tag $($artifactArgs -join ' ') --title `"$releaseTitle`" --notes `"$Notes`" --verify-tag --latest"
    Invoke-Expression $cmd
    Write-Host "GitHub Release đã tạo thành công!" -ForegroundColor Green
    
    # Bảng tổng kết kết hợp ảnh QR Code gửi 1 tin duy nhất
    $summary = @"
📱 <b>Ứng dụng:</b> $releaseTitle
🏷️ <b>Phiên bản:</b> <b>v$Version</b> (Git Tag: <code>$tag</code>)
🤖 <b>Nền tảng:</b> Android
📦 <b>Tệp đính kèm:</b> $(($artifacts | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')
📝 <b>Ghi chú:</b> $Notes

📲 <b>Cài đặt:</b>
1. <b>Quét mã QR trên</b> để tải trực tiếp file APK về máy.
2. Hoặc tải trực tiếp: <a href='$primaryDownloadUrl'>👉 Tải file APK tại đây</a>
🌐 <b>Bản phát hành GitHub:</b> <a href='$ghUrl'>Xem chi tiết trên GitHub</a>
"@
    Send-TgStep -Title "PHÁT HÀNH ANDROID THÀNH CÔNG" -Message $summary -Status "HOÀN TẤT" -QrCodeData $primaryDownloadUrl -PhotoPath $qrDestPath
} else {
    Write-Host "gh CLI không khả dụng. Đã push tag $tag lên remote." -ForegroundColor Yellow
}

# Nếu yêu cầu All (cả Android và iOS): Chạy tiếp iOS
if ($Platform -eq "all") {
    Write-Host "Platform là all: Tiếp tục kích hoạt build iOS cho admin-node..." -ForegroundColor Cyan
    $iosScript = Join-Path $PSScriptRoot "deploy_ios.ps1"
    & $iosScript -Version $Version -Notes $Notes -ChannelId $ChannelId -BotToken $BotToken
}

Write-Host "Phát hành $tag hoàn tất thành công!" -ForegroundColor Green
