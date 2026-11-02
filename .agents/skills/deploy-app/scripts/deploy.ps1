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
    Write-Host "Syncing Target Node version to $Version..." -ForegroundColor Cyan
    $targetGradlePath = Join-Path $repoRoot "target-node\app\build.gradle.kts"
    if (Test-Path $targetGradlePath) {
        $gradleContent = Get-Content -Path $targetGradlePath -Raw
        $gradleContent = $gradleContent -replace 'versionName\s*=\s*"[^"]+"', "versionName = `"$Version`""
        Set-Content -Path $targetGradlePath -Value $gradleContent -NoNewline
    }

    Write-Host "Building Target Node (VFam Child)..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "target-node")
    
    # Wipe any stale debug APK before build
    Remove-Item -Path (Join-Path $repoRoot "target-node\app\build\outputs\apk\debug\app-debug.apk") -Force -ErrorAction SilentlyContinue

    .\gradlew.bat assembleDebug
    if ($LASTEXITCODE -ne 0) {
        throw "Target Node build failed with exit code $LASTEXITCODE"
    }
    
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
    Write-Host "Syncing Admin Node version to $Version..." -ForegroundColor Cyan
    $adminPubspecPath = Join-Path $repoRoot "admin-node\pubspec.yaml"
    if (Test-Path $adminPubspecPath) {
        $pubContent = Get-Content -Path $adminPubspecPath -Raw
        $pubContent = $pubContent -replace 'version:\s*[0-9\.\+\-]+', "version: $Version+9"
        Set-Content -Path $adminPubspecPath -Value $pubContent -NoNewline
    }

    Write-Host "Building Admin Node (VFam Admin)..." -ForegroundColor Yellow
    Set-Location (Join-Path $repoRoot "admin-node")
    
    # Wipe any stale release APK before build
    Remove-Item -Path (Join-Path $repoRoot "admin-node\build\app\outputs\flutter-apk\app-release.apk") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $repoRoot "admin-node\build\app\outputs\apk\release\app-release.apk") -Force -ErrorAction SilentlyContinue

    flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk --release failed with exit code $LASTEXITCODE"
    }
    
    $adminApkPath = Join-Path $repoRoot "admin-node\build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $adminApkPath)) {
        $adminApkPath = Join-Path $repoRoot "admin-node\build\app\outputs\apk\release\app-release.apk"
    }
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
    Write-Host "Publishing GitHub Release via gh CLI..." -ForegroundColor Cyan
    $artifactArgs = $artifacts | ForEach-Object { "`"$_`"" }
    $cmd = "& `"$ghExe`" release create $tag $($artifactArgs -join ' ') --title `"$releaseTitle`" --notes `"$Notes`" --verify-tag"
    Invoke-Expression $cmd
    Write-Host "GitHub Release created successfully!" -ForegroundColor Green
} else {
    Write-Host "gh CLI not detected. Git tag $tag pushed. APKs saved in release/ directory for distribution." -ForegroundColor Yellow
}

Write-Host "Release $tag completed successfully!" -ForegroundColor Green
