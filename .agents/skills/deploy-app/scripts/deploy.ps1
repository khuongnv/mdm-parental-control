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
    "Child Agent Release v$Version"
} elseif ($Target -eq "admin") {
    "Parent Admin App Release v$Version"
} else {
    "MDM Full Release v$Version"
}

Write-Host "Starting Deploy: $Target ($tag)" -ForegroundColor Cyan

$artifacts = @()

if ($Target -eq "target" -or $Target -eq "all") {
    Write-Host "Building Target Node..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "target-node")
    .\gradlew.bat app:assembleDebug
    
    $targetApkPath = Join-Path $repoRoot "target-node\app\build\outputs\apk\debug\app-debug.apk"
    if (Test-Path $targetApkPath) {
        $destTargetApk = Join-Path $repoRoot "mdm-child-agent-$Version.apk"
        Copy-Item -Path $targetApkPath -Destination $destTargetApk -Force
        $artifacts += $destTargetApk
        Write-Host "Target Node APK ready: $destTargetApk" -ForegroundColor Green
    } else {
        throw "Target Node APK not found!"
    }
}

if ($Target -eq "admin" -or $Target -eq "all") {
    Write-Host "Building Admin Node via Android Gradle..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "admin-node\android")
    .\gradlew.bat app:assembleDebug
    
    $adminApkPath = Join-Path $repoRoot "admin-node\build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $adminApkPath) {
        $destAdminApk = Join-Path $repoRoot "mdm-parent-admin-$Version.apk"
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

Write-Host "Publishing GitHub Release via gh CLI..." -ForegroundColor Cyan
$artifactArgs = $artifacts | ForEach-Object { "`"$_`"" }
$cmd = "gh release create $tag $($artifactArgs -join ' ') --title `"$releaseTitle`" --notes `"$Notes`" --verify-tag"
Invoke-Expression $cmd

$artifacts | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Release $tag completed successfully!" -ForegroundColor Green
