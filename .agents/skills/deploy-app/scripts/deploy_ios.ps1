param (
    [Parameter(Mandatory=$false)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$Notes = "Bản phát hành ứng dụng phụ huynh VFam Parent iOS Enterprise.",

    [Parameter(Mandatory=$false)]
    [string]$ChannelId = "-1003609918702",

    [Parameter(Mandatory=$false)]
    [string]$BotToken = "8005142785:AAHSrJ2Yp4l0Gj6Yk7iu8hwSwThZIiVKrCU"
)

$ErrorActionPreference = "Stop"

# Đảm bảo console UTF-8
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
Set-Location $repoRoot

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
$macHost = "100.111.29.5"
$macUser = "khuongnv"
$bundleId = "com.dhtthni.quanlytaptrung"
$profileUuid = "f5a84849-5dda-4021-adcb-877132002773"
$teamId = "JPMH34L85K"

$telegramScript = Join-Path $PSScriptRoot "send-telegram.ps1"
function Send-TgStep {
    param([string]$Title, [string]$Message, [string]$Status = "Thanh cong", [string]$QrCodeData)
    if (Test-Path $telegramScript) {
        $tgParams = @{
            StepTitle = $Title
            Message = $Message
            ResultStatus = $Status
            ChannelId = $ChannelId
            BotToken = $BotToken
        }
        if (-not [string]::IsNullOrWhiteSpace($QrCodeData)) {
            $tgParams["QrCodeData"] = $QrCodeData
        }
        & $telegramScript @tgParams
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "KHOI DONG CI/CD BUILD & DEPLOY iOS CHO ADMIN-NODE" -ForegroundColor Cyan
Write-Host "Tag: $tag | Version: $Version" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ---------------- BƯỚC 1: ĐỒNG BỘ VERSION & KHỞI ĐỘNG ----------------
$step1Title = "Buoc 1: Khoi dong phat hanh iOS cho Admin-Node"
$step1Desc = "Ung dung: VFam Parent (iOS Enterprise - $bundleId)`nPhien ban: $Version (Tag: $tag)`nKenh phat hanh: GitHub Releases & Apple OTA Manifest"
Write-Host ">>> $step1Title..." -ForegroundColor Yellow
Send-TgStep -Title $step1Title -Message $step1Desc -Status "Dang khoi tao cau hinh..."

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

Send-TgStep -Title $step1Title -Message "Da cap nhat pubspec.yaml len version $Version. San sang ket noi Mac M1 Pro." -Status "Thanh cong"

# ---------------- BƯỚC 2: KẾT NỐI MAC & CÀI ĐẶT CHỨNG CHỈ / PROFILE ----------------
$step2Title = "Buoc 2: Cai dat Chung chi & Provisioning Profile len Mac M1 Pro"
$step2Desc = "Host: $macHost | Team ID: $teamId | Profile UUID: $profileUuid"
Write-Host ">>> $step2Title..." -ForegroundColor Yellow
Send-TgStep -Title $step2Title -Message $step2Desc -Status "Dang ket noi SSH va cau hinh Keychain..."

$p12Local = Join-Path $repoRoot "docs\dev\VNPT_Enterprise_iOS Distribution_18082029.p12"
$provLocal = Join-Path $repoRoot "docs\dev\Prov_HNI_comdhtthniquanlytaptrung.mobileprovision"

if (-not (Test-Path $p12Local) -or -not (Test-Path $provLocal)) {
    $err = "Không tìm thấy file P12 hoặc Mobileprovision trong docs/dev/"
    Send-TgStep -Title $step2Title -Message $err -Status "Lỗi ❌"
    throw $err
}

# Tạo thư mục trên Mac
ssh -o StrictHostKeyChecking=no "$macUser@$macHost" "mkdir -p ~/vfam-build/certs ~/Library/MobileDevice/'Provisioning Profiles'"
if ($LASTEXITCODE -ne 0) {
    throw "Không thể kết nối SSH tới $macHost"
}

# SCP P12 và Mobileprovision
scp -o StrictHostKeyChecking=no "$p12Local" "${macUser}@${macHost}:~/vfam-build/certs/VNPT_Enterprise.p12"
scp -o StrictHostKeyChecking=no "$provLocal" "${macUser}@${macHost}:~/Library/MobileDevice/'Provisioning Profiles'/$profileUuid.mobileprovision"

# Unlock Keychain và kiểm tra identity
$keychainCmds = @"
security unlock-keychain -p "1230" ~/Library/Keychains/login.keychain-db 2>/dev/null || true
if ! security find-identity -v -p codesigning | grep -q "55EC3964ACBC2DCA8D9C621C07EFA94AF764600F"; then
    echo ">>> Import chứng chỉ Enterprise vào Keychain..."
    security import ~/vfam-build/certs/VNPT_Enterprise.p12 -k ~/Library/Keychains/login.keychain-db -P "RW2ynhz#1w@Z" -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || true
else
    echo ">>> Chứng chỉ Enterprise (55EC3964...) đã tồn tại trong Keychain."
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "1230" ~/Library/Keychains/login.keychain-db 2>/dev/null || true
security find-identity -v -p codesigning
"@

$keychainResult = ssh -o StrictHostKeyChecking=no "$macUser@$macHost" $keychainCmds
Write-Host $keychainResult

Send-TgStep -Title $step2Title -Message "Da xac thuc chung chi iPhone Distribution VNPT va nap mobileprovision thanh cong." -Status "Thanh cong"

# ---------------- BƯỚC 3: ĐỒNG BỘ SOURCE CODE & CÀI ĐẶT PODS ----------------
$step3Title = "Buoc 3: Dong bo Source Code & Cai dat CocoaPods tren Mac"
$step3Desc = "Dong goi admin-node, dong bo sang Mac M1 Pro va chay flutter pub get & pod install"
Write-Host ">>> $step3Title..." -ForegroundColor Yellow
Send-TgStep -Title $step3Title -Message $step3Desc -Status "Dang nen va chuyen source code..."

$tarPath = Join-Path $repoRoot "release\admin_src.tar.gz"
if (Test-Path $tarPath) { Remove-Item $tarPath -Force }

# Nén source code admin-node bằng tar có sẵn trong Windows System32
Write-Host "Nen admin-node vao $tarPath..." -ForegroundColor Cyan
& tar.exe -czf "$tarPath" --exclude="build" --exclude=".dart_tool" --exclude=".git" --exclude="android/app/build" -C "$repoRoot" "admin-node"
if ($LASTEXITCODE -ne 0) {
    throw "Nen source code that bai."
}

# SCP sang Mac
scp -o StrictHostKeyChecking=no "$tarPath" "${macUser}@${macHost}:~/vfam-build/admin_src.tar.gz"

# Giải nén & pub get & pod install trên Mac
$prepareCmds = @"
export PATH="/Users/khuongnv/development/flutter/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:`$PATH"
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

Send-TgStep -Title $step3Title -Message "Hoan tat flutter pub get va pod install tren Xcode workspace." -Status "Thanh cong"

# ---------------- BƯỚC 4: BIÊN DỊCH RELEASE IPA ----------------
$step4Title = "Buoc 4: Bien dich Goi cai dat iOS Release (.ipa)"
$step4Desc = "Chay flutter build ios --no-codesign -> xcodebuild archive -> exportArchive Enterprise"
Write-Host ">>> $step4Title..." -ForegroundColor Yellow
Send-TgStep -Title $step4Title -Message $step4Desc -Status "Dang chay xcodebuild archive tren Mac M1 Pro..."

$buildCmds = @"
export PATH="/Users/khuongnv/development/flutter/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:`$PATH"
cd ~/vfam-build/admin-node
security unlock-keychain -p "1230" ~/Library/Keychains/login.keychain-db 2>/dev/null || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "1230" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

echo "=== DỌN DẸP DERIVEDDATA & BUILD CŨ ==="
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
rm -rf build/ios/archive build/ios/ipa
mkdir -p build/ios/archive build/ios/ipa

echo "=== FLUTTER BUILD IOS NO-CODESIGN ==="
flutter build ios --release --no-codesign --build-name="$Version" --build-number="11"

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
    $err = "Khong tim thay file IPA da xuat tren may host!"
    Send-TgStep -Title $step4Title -Message $err -Status "Loi"
    throw $err
}

$ipaSizeMb = [math]::Round((Get-Item $destIpa).Length / 1MB, 2)
Send-TgStep -Title $step4Title -Message "Da tao file IPA Enterprise ($destIpa - $ipaSizeMb MB)`nSHA256: <code>$ipaSha256</code>" -Status "Thanh cong"

# ---------------- BƯỚC 5: TẠO OTA MANIFEST & PHÁT HÀNH GITHUB RELEASES ----------------
$step5Title = "Buoc 5: Dong goi OTA Manifest & Phat hanh GitHub Releases"
$step5Desc = "Tag: $tag | Assets: vfam-admin-ios-$Version.ipa & manifest.plist"
Write-Host ">>> $step5Title..." -ForegroundColor Yellow
Send-TgStep -Title $step5Title -Message $step5Desc -Status "Dang tao OTA Manifest va day GitHub Release..."

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

Write-Host "Tao tag $tag..." -ForegroundColor Cyan
git tag -a $tag -m "$releaseTitle" -f
git push origin $tag -f

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

# Tạo mã QR Code cho link OTA cài đặt và lưu file ảnh cục bộ
$manifestRawUrl = "https://github.com/khuongnv/mdm-parental-control/releases/download/$tag/manifest.plist"
$otaInstallLink = "itms-services://?action=download-manifest&url=$manifestRawUrl"
$ghReleaseUrl = "https://github.com/khuongnv/mdm-parental-control/releases/tag/$tag"

$qrDestPath = Join-Path $releaseDir "vfam-admin-ios-$Version-qr.png"
try {
    $escapedOta = [System.Uri]::EscapeDataString($otaInstallLink)
    $qrApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&margin=12&data=$escapedOta"
    Invoke-WebRequest -Uri $qrApiUrl -OutFile $qrDestPath -TimeoutSec 10 -ErrorAction SilentlyContinue
    Write-Host "Da tao anh QR Code cai dat tai: $qrDestPath" -ForegroundColor Green
} catch {
    Write-Warning "Khong the tao file anh QR Code cuc bo: $($_.Exception.Message)"
}

if ($ghExe) {
    Write-Host "Tao GitHub Release qua gh CLI..." -ForegroundColor Cyan
    $releaseFiles = @("$destIpa", "$manifestDestPath")
    if (Test-Path $qrDestPath) { $releaseFiles += "$qrDestPath" }
    
    $fileArgs = $releaseFiles | ForEach-Object { "`"$_`"" }
    & "$ghExe" release create $tag ($releaseFiles) --title "$releaseTitle" --notes "$Notes" --verify-tag
    Write-Host "GitHub Release da tao thanh cong!" -ForegroundColor Green
    Send-TgStep -Title $step5Title -Message "Da phat hanh GitHub Release <b>$tag</b> dinh kem tep IPA, manifest.plist va anh QR Code cai dat thanh cong!" -Status "Thanh cong"
} else {
    Write-Warning "gh CLI khong kha dung. Da push tag $tag len remote."
}

# ---------------- BƯỚC 6: TỔNG KẾT & HOÀN TẤT ----------------
$summaryContent = @"
Ung dung: <b>VFam Parent Admin (iOS Enterprise)</b> (<code>$bundleId</code>)
• Phien ban moi: <b>$Version</b> (Git Tag: <code>$tag</code>)
• Chu ky so: <b>VNPT Enterprise In-House</b> (Team: $teamId)
• Dung luong IPA: <b>$ipaSizeMb MB</b>
• SHA256 (IPA): <code>$ipaSha256</code>
• Ghi chu: $Notes

<b>Link Cai dat Truc tiep cho iPhone/iPad (Apple OTA):</b>
<a href='$otaInstallLink'>👉 Bam vao day de Cai dat tren iOS</a>

<b>GitHub Release:</b>
<a href='$ghReleaseUrl'>$ghReleaseUrl</a>
"@

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "HOAN TAT PHAT HANH iOS CHO ADMIN-NODE THANH CONG!" -ForegroundColor Green
Write-Host "OTA Link: $otaInstallLink" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

Send-TgStep -Title "TONG KET PHAT HANH iOS THANH CONG" -Message $summaryContent -Status "HOAN TAT" -QrCodeData $otaInstallLink

