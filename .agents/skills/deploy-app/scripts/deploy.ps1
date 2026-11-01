<#
.SYNOPSIS
    Kịch bản tự động build, gắn tag và phát hành (release) phiên bản độc lập cho target-node hoặc admin-node lên GitHub Releases.

.PARAMETER Target
    Ứng dụng cần deploy: "target" (Child DO Agent), "admin" (Parent App), hoặc "all".

.PARAMETER Version
    Phiên bản ngữ nghĩa (Semantic Versioning), ví dụ: "1.0.1", "1.1.0".

.PARAMETER Notes
    Ghi chú phát hành (Release Notes).

.EXAMPLE
    .\deploy.ps1 -Target target -Version "1.0.1" -Notes "Cải tiến chống gỡ app và sửa lỗi tracking"
    .\deploy.ps1 -Target admin -Version "1.0.2" -Notes "Bổ sung biểu đồ trực quan"
#>

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("target", "admin", "all")]
    [string]$Target,

    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$Notes = "Bản phát hành cập nhật tự động."
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
Set-Location $repoRoot

# Chuẩn hóa tag name: target-vX.Y.Z hoặc admin-vX.Y.Z hoặc vX.Y.Z
$tag = if ($Target -eq "all") { "v$Version" } else { "$Target-v$Version" }
$releaseTitle = if ($Target -eq "target") {
    "Child Agent Release v$Version"
} elseif ($Target -eq "admin") {
    "Parent Admin App Release v$Version"
} else {
    "MDM Full Release v$Version"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🚀 BẮT ĐẦU QUY TRÌNH DEPLOY APP: $Target ($tag)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$artifacts = @()

# 1. Build Target Node nếu được yêu cầu
if ($Target -eq "target" -or $Target -eq "all") {
    Write-Host "`n📦 [1/3] Đang build Target Node (Child Device Owner Agent)..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "target-node")
    
    # Nâng versionCode và versionName nếu cần trong app/build.gradle.kts
    $gradlew = if ($IsWindows -or $env:OS -like "*Windows*") { ".\gradlew.bat" } else { "./gradlew" }
    & $gradlew app:assembleDebug
    
    $targetApkPath = Join-Path $repoRoot "target-node\app\build\outputs\apk\debug\app-debug.apk"
    if (Test-Path $targetApkPath) {
        $destTargetApk = Join-Path $repoRoot "mdm-child-agent-$Version.apk"
        Copy-Item -Path $targetApkPath -Destination $destTargetApk -Force
        $artifacts += $destTargetApk
        Write-Host "✅ Build Target Node thành công: $destTargetApk" -ForegroundColor Green
    } else {
        throw "Không tìm thấy file APK sau khi build target-node!"
    }
}

# 2. Build Admin Node nếu được yêu cầu
if ($Target -eq "admin" -or $Target -eq "all") {
    Write-Host "`n📦 [2/3] Đang build Admin Node (Parent Flutter App)..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "admin-node")
    
    flutter build apk --debug
    $adminApkPath = Join-Path $repoRoot "admin-node\build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $adminApkPath) {
        $destAdminApk = Join-Path $repoRoot "mdm-parent-admin-$Version.apk"
        Copy-Item -Path $adminApkPath -Destination $destAdminApk -Force
        $artifacts += $destAdminApk
        Write-Host "✅ Build Admin Node thành công: $destAdminApk" -ForegroundColor Green
    } else {
        throw "Không tìm thấy file APK sau khi build admin-node!"
    }
}

Set-Location $repoRoot

# 3. Tạo Git Tag và Phát hành GitHub Release qua GitHub CLI (gh)
Write-Host "`n🏷️ [3/3] Tạo Tag và Publish lên GitHub Release..." -ForegroundColor Yellow

# Kiểm tra git status
$status = git status --porcelain
if ($status) {
    Write-Host "⚠️ Phát hiện thay đổi chưa commit, đang tiến hành commit trước khi gắn tag..." -ForegroundColor DarkYellow
    git add .
    git commit -m "chore(release): bump version to $tag"
    git push origin main
}

# Tạo tag và đẩy lên git
Write-Host "Gắn git tag: $tag" -ForegroundColor Cyan
git tag -a $tag -m "$releaseTitle" -f
git push origin $tag -f

# Sử dụng gh release create
$artifactArgs = $artifacts | ForEach-Object { "`"$_`"" }
$ghCmd = "gh release create $tag $($artifactArgs -join ' ') --title `"$releaseTitle`" --notes `"$Notes`" --verify-tag"

Write-Host "Chạy lệnh phát hành GitHub Release..." -ForegroundColor Cyan
Invoke-Expression $ghCmd

# Dọn dẹp tệp APK tạm ngoài repo root
$artifacts | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n🎉 DEPLOY HOÀN TẤT THÀNH CÔNG CHO $tag!" -ForegroundColor Green
Write-Host "GitHub Release đã được publish kèm artifacts để app tự động phát hiện cập nhật." -ForegroundColor Green
