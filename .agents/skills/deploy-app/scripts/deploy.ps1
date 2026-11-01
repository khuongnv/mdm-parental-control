param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("target", "admin", "all")]
    [string]$Target,

    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$Notes = "Initial Release"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
Set-Location $repoRoot

$tag = if ($Target -eq "all") { "v$Version" } else { "$Target-v$Version" }
$releaseTitle = if ($Target -eq "target") {
    "VFam Child Agent Release v$Version"
} elseif ($Target -eq "admin") {
    "VFam Parent Admin App Release v$Version"
} else {
    "VFam Parental Control Release v$Version"
}

Write-Host "Starting Deploy: $Target ($tag)" -ForegroundColor Cyan

$artifacts = @()
$releaseDir = Join-Path $repoRoot "release"
if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Force $releaseDir | Out-Null
}

if ($Target -eq "target" -or $Target -eq "all") {
    Write-Host "Building Target Node (VFam Child)..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "target-node")
    .\gradlew.bat assembleDebug
    
    $targetApkPath = Join-Path $repoRoot "target-node\app\build\outputs\apk\debug\app-debug.apk"
    if (Test-Path $targetApkPath) {
        $destTargetApk = Join-Path $releaseDir "vfam-child-$Version.apk"
        Copy-Item -Path $targetApkPath -Destination $destTargetApk -Force
        $artifacts += $destTargetApk
        Write-Host "Target Node APK ready: $destTargetApk" -ForegroundColor Green
    } else {
        throw "Target Node APK not found!"
    }
}

if ($Target -eq "admin" -or $Target -eq "all") {
    Write-Host "Building Admin Node (VFam Admin) via Flutter..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "admin-node")
    flutter build apk --debug
    
    $adminApkPath = Join-Path $repoRoot "admin-node\build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $adminApkPath) {
        $destAdminApk = Join-Path $releaseDir "vfam-admin-$Version.apk"
        Copy-Item -Path $adminApkPath -Destination $destAdminApk -Force
        $artifacts += $destAdminApk
        Write-Host "Admin Node APK ready: $destAdminApk" -ForegroundColor Green
    } else {
        throw "Admin Node APK not found!"
    }
}

Set-Location $repoRoot

$status = git status --porcelain
if ($status) {
    git add .
    git commit -m "chore(release): bump version to $tag"
    git push origin main
}

Write-Host "Creating git tag $tag" -ForegroundColor Cyan
git tag -a $tag -m "$releaseTitle" -f
git push origin $tag -f

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "Publishing GitHub Release via gh CLI..." -ForegroundColor Cyan
    $artifactArgs = $artifacts | ForEach-Object { "`"$_`"" }
    $cmd = "gh release create $tag $($artifactArgs -join ' ') --title `"$releaseTitle`" --notes `"$Notes`" --verify-tag"
    Invoke-Expression $cmd
    Write-Host "GitHub Release created successfully!" -ForegroundColor Green
} else {
    Write-Host "gh CLI not detected. Git tag $tag pushed. APKs saved in release/ directory for distribution." -ForegroundColor Yellow
}

Write-Host "Release $tag completed successfully!" -ForegroundColor Green
