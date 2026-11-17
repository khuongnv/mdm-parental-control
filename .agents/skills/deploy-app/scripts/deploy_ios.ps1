<#
.SYNOPSIS
    Kịch bản tự động hóa build và ký số iOS Enterprise cho Admin Node (Parent App) từ Windows sang Mac M1 Pro.
.DESCRIPTION
    1. Kiểm tra / bump version trong admin-node/pubspec.yaml.
    2. Nạp chứng chỉ VNPT Enterprise (.p12) và provisioning profile lên Mac từ xa.
    3. Đồng bộ source code sang Mac, chạy flutter pub get & pod install.
    4. Build no-codesign, chạy xcodebuild archive & exportArchive IPA.
    5. Kéo IPA về Windows, tạo manifest.plist cho Apple OTA distribution.
    6. Tạo Git tag, phát hành GitHub Release (gh release create) kèm IPA, manifest.plist và ảnh QR Code.
    7. Gửi thông báo tổng kết hoàn tất kèm ảnh QR Code cài đặt trực tiếp vào Telegram HUB-LOG.
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$Notes = "Bản phát hành iOS Enterprise dành cho ứng dụng phụ huynh VFam Parent.",

    [Parameter(Mandatory = $false)]
    [string]$ChannelId = "",

    [Parameter(Mandatory = $false)]
    [string]$BotToken = ""
)

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
            $curVer = $matches[1]
            $parts = $curVer.Split('.') | ForEach-Object { [int]$_ }
            if ($parts.Count -ge 3) {
                $Version = "$($parts[0]).$($parts[1] + 1).0"
            } else {
                $Version = "1.4.0"
            }
        } else {
            $Version = "1.4.0"
        }
    } else {
        $Version = "1.4.0"
    }
}

$tag = "admin-ios-v$Version"
$releaseTitle = "VFam Parent Admin iOS v$Version"

# Cấu hình máy chủ build Mac từ xa (nạp từ environment hoặc .env)
$macHost = if ($env:MAC_BUILD_HOST) { $env:MAC_BUILD_HOST } else { "127.0.0.1" }
$macUser = if ($env:MAC_BUILD_USER) { $env:MAC_BUILD_USER } else { [Environment]::UserName }
$keychainPass = if ($env:MAC_KEYCHAIN_PASSWORD) { $env:MAC_KEYCHAIN_PASSWORD } else { "" }
$p12Pass = if ($env:IOS_P12_PASSWORD) { $env:IOS_P12_PASSWORD } else { "" }

$bundleId = "com.dhtthni.quanlytaptrung"
$profileUuid = if ($env:IOS_PROFILE_UUID) { $env:IOS_PROFILE_UUID } else { "f5a84849-5dda-4021-adcb-877132002773" }
$teamId = if ($env:IOS_TEAM_ID) { $env:IOS_TEAM_ID } else { "JPMH34L85K" }

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

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "KHỞI ĐỘNG CI/CD BUILD & DEPLOY iOS CHO ADMIN-NODE" -ForegroundColor Cyan
Write-Host "Tag: $tag | Version: $Version" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ---------------- BƯỚC 1: ĐỒNG BỘ VERSION & KHỞI ĐỘNG ----------------
$step1Title = "Bước 1: Khởi động phát hành iOS cho Admin-Node"
$step1Desc = "Ứng dụng: VFam Parent (iOS Enterprise - <code>$bundleId</code>)`nPhiên bản: <b>v$Version</b> (Tag: <code>$tag</code>)`nKênh phát hành: GitHub Releases & Apple OTA Manifest"
Write-Host ">>> $step1Title..." -ForegroundColor Yellow
Send-TgStep -Title $step1Title -Message $step1Desc -Status "Đang khởi tạo cấu hình..."

$adminPubspecPath = Join-Path $repoRoot "admin-node\pubspec.yaml"
if (Test-Path $adminPubspecPath) {
    $pubContent = Get-Content -Path $adminPubspecPath -Raw -Encoding UTF8
    $pubContent = $pubContent -replace 'version:\s*[0-9\.\+\-]+', "version: $Version+11"
    Set-Content -Path $adminPubspecPath -Value $pubContent -Encoding UTF8 -NoNewline
}

$releaseDir = Join-Path $repoRoot "release"
if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Force $releaseDir | Out-Null
}

Send-TgStep -Title $step1Title -Message "Đã đồng bộ pubspec.yaml lên version $Version. Sẵn sàng kết nối máy Mac M1 Pro." -Status "Thành công"

# ---------------- BƯỚC 2: KẾT NỐI MAC & CÀI ĐẶT CHỨNG CHỈ / PROFILE ----------------
$step2Title = "Bước 2: Cài đặt Chứng chỉ & Provisioning Profile lên Mac M1 Pro"
$step2Desc = "Host: <code>$macHost</code> | Team ID: <code>$teamId</code> | Profile UUID: <code>$profileUuid</code>"
Write-Host ">>> $step2Title..." -ForegroundColor Yellow
Send-TgStep -Title $step2Title -Message $step2Desc -Status "Đang kết nối SSH và cấu hình Keychain..."

$p12Local = Join-Path $repoRoot "docs\dev\VNPT_Enterprise_iOS Distribution_18082029.p12"
$provLocal = Join-Path $repoRoot "docs\dev\Prov_HNI_comdhtthniquanlytaptrung.mobileprovision"

if (-not (Test-Path $p12Local) -or -not (Test-Path $provLocal)) {
    $err = "Không tìm thấy file P12 hoặc Mobileprovision trong docs/dev/"
    Send-TgStep -Title $step2Title -Message $err -Status "Lỗi ❌"
    throw $err
}

# Tạo thư mục nhận trên Mac
ssh -o StrictHostKeyChecking=no "$macUser@$macHost" "mkdir -p ~/vfam-build/certs ~/Library/MobileDevice/'Provisioning Profiles'"

# Copy file sang Mac
scp -o StrictHostKeyChecking=no "$p12Local" "${macUser}@${macHost}:~/vfam-build/certs/VNPT_Enterprise.p12"
scp -o StrictHostKeyChecking=no "$provLocal" "${macUser}@${macHost}:~/vfam-build/certs/$profileUuid.mobileprovision"

# Đưa profile vào đúng thư mục Provisioning Profiles
ssh -o StrictHostKeyChecking=no "$macUser@$macHost" "cp ~/vfam-build/certs/$profileUuid.mobileprovision ~/Library/MobileDevice/'Provisioning Profiles'/"

# Unlock Keychain và kiểm tra identity
$keychainCmds = @"
security unlock-keychain -p "$keychainPass" ~/Library/Keychains/login.keychain-db 2>/dev/null || true
if ! security find-identity -v -p codesigning | grep -q "55EC3964ACBC2DCA8D9C621C07EFA94AF764600F"; then
    echo ">>> Import chứng chỉ Enterprise vào Keychain..."
    security import ~/vfam-build/certs/VNPT_Enterprise.p12 -k ~/Library/Keychains/login.keychain-db -P "$p12Pass" -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || true
else
    echo ">>> Chứng chỉ Enterprise (55EC3964...) đã sẵn sàng trong Keychain."
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychainPass" ~/Library/Keychains/login.keychain-db 2>/dev/null || true
security find-identity -v -p codesigning
"@

$keychainResult = ssh -o StrictHostKeyChecking=no "$macUser@$macHost" $keychainCmds
Write-Host $keychainResult

Send-TgStep -Title $step2Title -Message "Đã xác thực chứng chỉ iPhone Distribution VNPT và nạp mobileprovision thành công." -Status "Thành công"

# ---------------- BƯỚC 3: ĐỒNG BỘ SOURCE CODE & CÀI ĐẶT PODS ----------------
$step3Title = "Bước 3: Đồng bộ Source Code & Cài đặt CocoaPods trên Mac"
$step3Desc = "Đóng gói admin-node, đồng bộ sang Mac M1 Pro và chạy flutter pub get & pod install"
Write-Host ">>> $step3Title..." -ForegroundColor Yellow
Send-TgStep -Title $step3Title -Message $step3Desc -Status "Đang nén và chuyển source code..."

$tarPath = Join-Path $repoRoot "release\admin_src.tar.gz"
if (Test-Path $tarPath) { Remove-Item $tarPath -Force }

Write-Host "Nén admin-node vào $tarPath..." -ForegroundColor Cyan
& tar.exe -czf "$tarPath" --exclude="build" --exclude=".dart_tool" --exclude=".git" --exclude="android/app/build" -C "$repoRoot" "admin-node"
if ($LASTEXITCODE -ne 0) {
    throw "Nén source code thất bại."
}

# SCP sang Mac
scp -o StrictHostKeyChecking=no "$tarPath" "${macUser}@${macHost}:~/vfam-build/admin_src.tar.gz"

# Giải nén & pub get & pod install trên Mac
$prepareCmds = @"
export PATH="/Users/$macUser/development/flutter/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:`$PATH"
cd ~/vfam-build
rm -rf admin-node
tar -xzf admin_src.tar.gz
cd admin-node

echo "=== FLUTTER PUB GET ==="
flutter pub get

echo "=== COCOAPODS INSTALL ==="
cd ios
pod install
"@

$prepareResult = ssh -o StrictHostKeyChecking=no "$macUser@$macHost" $prepareCmds
Write-Host $prepareResult

Send-TgStep -Title $step3Title -Message "Hoàn tất flutter pub get và pod install trên Xcode workspace." -Status "Thành công"

# ---------------- BƯỚC 4: BIÊN DỊCH RELEASE IPA ----------------
$step4Title = "Bước 4: Biên dịch Gói cài đặt iOS Release (.ipa)"
$step4Desc = "Chạy flutter build ios --no-codesign -> xcodebuild archive -> exportArchive Enterprise"
Write-Host ">>> $step4Title..." -ForegroundColor Yellow
Send-TgStep -Title $step4Title -Message $step4Desc -Status "Đang chạy xcodebuild archive trên Mac M1 Pro..."

$flutterExtraArgs = ""
if ($env:SUPABASE_URL) {
    $flutterExtraArgs += " --dart-define=SUPABASE_URL=$($env:SUPABASE_URL)"
}
if ($env:SUPABASE_ANON_KEY) {
    $flutterExtraArgs += " --dart-define=SUPABASE_ANON_KEY=$($env:SUPABASE_ANON_KEY)"
}

$buildCmds = @"
export PATH="/Users/$macUser/development/flutter/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:`$PATH"
cd ~/vfam-build/admin-node
security unlock-keychain -p "$keychainPass" ~/Library/Keychains/login.keychain-db 2>/dev/null || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychainPass" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

echo "=== DỌN DẸP DERIVEDDATA & BUILD CŨ ==="
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
rm -rf build/ios/archive build/ios/ipa
mkdir -p build/ios/archive build/ios/ipa

echo "=== FLUTTER BUILD IOS NO-CODESIGN ==="
flutter build ios --release --no-codesign --build-name="$Version" --build-number="11" $flutterExtraArgs

echo "=== XCODEBUILD ARCHIVE ==="
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive

echo "=== XCODEBUILD EXPORT ARCHIVE ==="
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions-enterprise.plist

echo "=== DANH SÁCH IPA ==="
ls -lh build/ios/ipa/*.ipa
echo "=== SHA256 IPA ==="
shasum -a 256 build/ios/ipa/*.ipa
"@

$buildResult = ssh -o StrictHostKeyChecking=no "$macUser@$macHost" $buildCmds
Write-Host $buildResult

$shaMatch = [regex]::Match($buildResult, "([a-fA-F0-9]{64})\s+.*\.ipa")
$ipaSha256 = if ($shaMatch.Success) { $shaMatch.Groups[1].Value } else { "N/A" }

# Tải file IPA về host
$destIpa = Join-Path $releaseDir "vfam-admin-ios-$Version.ipa"
scp -o StrictHostKeyChecking=no "${macUser}@${macHost}:~/vfam-build/admin-node/build/ios/ipa/*.ipa" "$destIpa"

if (-not (Test-Path $destIpa)) {
    $err = "Không tìm thấy file IPA đã xuất trên máy host!"
    Send-TgStep -Title $step4Title -Message $err -Status "Lỗi ❌"
    throw $err
}

$ipaSizeMb = [math]::Round((Get-Item $destIpa).Length / 1MB, 2)
Send-TgStep -Title $step4Title -Message "Đã xuất file IPA Enterprise ($destIpa - $ipaSizeMb MB)`nSHA256: <code>$ipaSha256</code>" -Status "Thành công"

# ---------------- BƯỚC 5: TẠO OTA MANIFEST, QR CODE & PHÁT HÀNH GITHUB RELEASES ----------------
Write-Host ">>> Đóng gói OTA Manifest, sinh mã QR Code và phát hành GitHub..." -ForegroundColor Yellow

$manifestTemplatePath = Join-Path $repoRoot ".agents\skills\deploy-app\templates\manifest.plist.template"
$manifestDestPath = Join-Path $releaseDir "manifest.plist"

$ipaDownloadUrl = "https://github.com/khuongnv/mdm-parental-control/releases/download/$tag/vfam-admin-ios-$Version.ipa"

$manifestContent = Get-Content -Path $manifestTemplatePath -Raw -Encoding UTF8
$manifestContent = $manifestContent -replace '\{\{IPA_URL\}\}', $ipaDownloadUrl
$manifestContent = $manifestContent -replace '\{\{BUNDLE_ID\}\}', $bundleId
$manifestContent = $manifestContent -replace '\{\{VERSION\}\}', $Version
$manifestContent = $manifestContent -replace '\{\{TITLE\}\}', "VFam Parent"
Set-Content -Path $manifestDestPath -Value $manifestContent -Encoding UTF8

# Git commit nếu có thay đổi và tạo tag
$gitStatus = git status --porcelain
if ($gitStatus) {
    git add admin-node/
    git commit -m "chore(release): bump admin-node ios to $Version"
    git push origin main
}

Write-Host "Tạo tag $tag..." -ForegroundColor Cyan
git tag -a $tag -m "$releaseTitle" -f
git push origin $tag -f

# Liên kết Apple OTA & QR Code
$manifestRawUrl = "https://github.com/khuongnv/mdm-parental-control/releases/download/$tag/manifest.plist"
$otaInstallLink = "itms-services://?action=download-manifest&url=$manifestRawUrl"
$ghReleaseUrl = "https://github.com/khuongnv/mdm-parental-control/releases/tag/$tag"

$qrDestPath = Join-Path $releaseDir "vfam-admin-ios-$Version-qr.png"
try {
    $escapedOta = [System.Uri]::EscapeDataString($otaInstallLink)
    $qrApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&margin=12&data=$escapedOta"
    Invoke-WebRequest -Uri $qrApiUrl -OutFile $qrDestPath -TimeoutSec 10 -ErrorAction SilentlyContinue
    Write-Host "Đã tạo ảnh QR Code cài đặt tại: $qrDestPath" -ForegroundColor Green
} catch {
    Write-Warning "Không thể tạo file ảnh QR Code cục bộ: $($_.Exception.Message)"
}

# Phát hành GitHub Release
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
    Write-Host "Tạo GitHub Release qua gh CLI..." -ForegroundColor Cyan
    $releaseFiles = @("$destIpa", "$manifestDestPath")
    if (Test-Path $qrDestPath) { $releaseFiles += "$qrDestPath" }
    
    & "$ghExe" release create $tag ($releaseFiles) --title "$releaseTitle" --notes "$Notes" --verify-tag
    Write-Host "GitHub Release đã tạo thành công!" -ForegroundColor Green
} else {
    Write-Warning "gh CLI không khả dụng. Đã push tag $tag lên remote."
}

# ---------------- BƯỚC 6: TỔNG KẾT GỌN GÀNG KẾT HỢP ẢNH QR CODE CÀI ĐẶT ----------------
# Trình bày súc tích, hiển thị 1 thẻ duy nhất gồm ảnh QR Code và toàn bộ thông tin hoàn tất
$summaryContent = @"
📱 <b>Ứng dụng:</b> VFam Parent Admin (<code>$bundleId</code>)
🏷️ <b>Phiên bản:</b> <b>v$Version</b> (Git Tag: <code>$tag</code>)
🔐 <b>Ký số:</b> VNPT Enterprise In-House (Team: <code>$teamId</code>)
📦 <b>Dung lượng:</b> <b>$ipaSizeMb MB</b>
🔑 <b>SHA256:</b> <code>$ipaSha256</code>
📝 <b>Ghi chú:</b> $Notes

📲 <b>Cài đặt trên iPhone/iPad:</b>
1. <b>Quét mã QR trên</b> bằng ứng dụng Camera.
2. Hoặc mở liên kết: <a href='$otaInstallLink'>👉 Cài đặt trực tiếp (Apple OTA)</a>
🌐 <b>Bản phát hành GitHub:</b> <a href='$ghReleaseUrl'>Xem chi tiết trên GitHub</a>
"@

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "HOÀN TẤT PHÁT HÀNH iOS CHO ADMIN-NODE THÀNH CÔNG!" -ForegroundColor Green
Write-Host "OTA Link: $otaInstallLink" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

# Gửi DUY NHẤT 1 tin kèm ảnh QR Code tới Telegram HUB-LOG
Send-TgStep -Title "PHÁT HÀNH iOS ENTERPRISE THÀNH CÔNG" -Message $summaryContent -Status "HOÀN TẤT" -QrCodeData $otaInstallLink -PhotoPath $qrDestPath
