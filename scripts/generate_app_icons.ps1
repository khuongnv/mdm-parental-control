Add-Type -AssemblyName System.Drawing

function Resize-Image {
    param(
        [System.Drawing.Image]$source,
        [int]$targetWidth,
        [int]$targetHeight,
        [string]$outputPath
    )
    $destRect = [System.Drawing.Rectangle]::new(0, 0, $targetWidth, $targetHeight)
    $destBmp = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
    $destBmp.SetResolution($source.HorizontalResolution, $source.VerticalResolution)

    $g = [System.Drawing.Graphics]::FromImage($destBmp)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $wrapMode = New-Object System.Drawing.Imaging.ImageAttributes
    $wrapMode.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)

    $g.DrawImage($source, $destRect, 0, 0, $source.Width, $source.Height, [System.Drawing.GraphicsUnit]::Pixel, $wrapMode)
    $g.Dispose()
    $wrapMode.Dispose()

    $parentDir = [System.IO.Path]::GetDirectoryName($outputPath)
    if (-not [System.IO.Directory]::Exists($parentDir)) {
        [System.IO.Directory]::CreateDirectory($parentDir) | Out-Null
    }

    $destBmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $destBmp.Dispose()
    Write-Output "Generated: $outputPath ($($targetWidth)x$($targetHeight))"
}

# 1. Child App Icons
$childSourcePath = "C:\Users\khuongnv\.gemini\antigravity\brain\17e64546-7f5a-4ea4-b26c-75272084700e\child_mode_clean_1794885890052.jpg"
$childImg = [System.Drawing.Image]::FromFile($childSourcePath)

# Save master copies
Resize-Image $childImg 1024 1024 "docs/branding/vfam_child_icon.png"
Resize-Image $childImg 1024 1024 "docs/icons/vfam_child_clean.png"

# Target-node mipmaps
$androidDensities = [ordered]@{
    "mipmap-mdpi" = 48
    "mipmap-hdpi" = 72
    "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144
    "mipmap-xxxhdpi" = 192
}

foreach ($dirName in $androidDensities.Keys) {
    $size = $androidDensities[$dirName]
    Resize-Image $childImg $size $size "target-node/app/src/main/res/$dirName/ic_launcher.png"
    Resize-Image $childImg $size $size "target-node/app/src/main/res/$dirName/ic_launcher_round.png"
}
$childImg.Dispose()

# 2. Admin App Icons (Android, iOS, Web)
$adminSourcePath = "docs/icons/Biểu tượng gia đình an toàn số.png"
$adminImg = [System.Drawing.Image]::FromFile($adminSourcePath)

# Save master copies
Resize-Image $adminImg 1024 1024 "docs/branding/vfam_admin_icon.png"
Resize-Image $adminImg 1024 1024 "docs/icons/vfam_admin_clean.png"

# Admin Android mipmaps
foreach ($dirName in $androidDensities.Keys) {
    $size = $androidDensities[$dirName]
    Resize-Image $adminImg $size $size "admin-node/android/app/src/main/res/$dirName/ic_launcher.png"
}

# Admin iOS AppIcons
$iosIcons = [ordered]@{
    "Icon-App-20x20@1x.png" = 20
    "Icon-App-20x20@2x.png" = 40
    "Icon-App-20x20@3x.png" = 60
    "Icon-App-29x29@1x.png" = 29
    "Icon-App-29x29@2x.png" = 58
    "Icon-App-29x29@3x.png" = 87
    "Icon-App-40x40@1x.png" = 40
    "Icon-App-40x40@2x.png" = 80
    "Icon-App-40x40@3x.png" = 120
    "Icon-App-60x60@2x.png" = 120
    "Icon-App-60x60@3x.png" = 180
    "Icon-App-76x76@1x.png" = 76
    "Icon-App-76x76@2x.png" = 152
    "Icon-App-83.5x83.5@2x.png" = 167
    "Icon-App-1024x1024@1x.png" = 1024
}

foreach ($fileName in $iosIcons.Keys) {
    $size = $iosIcons[$fileName]
    Resize-Image $adminImg $size $size "admin-node/ios/Runner/Assets.xcassets/AppIcon.appiconset/$fileName"
}

# Admin Web icons
Resize-Image $adminImg 192 192 "admin-node/web/icons/Icon-192.png"
Resize-Image $adminImg 512 512 "admin-node/web/icons/Icon-512.png"
Resize-Image $adminImg 192 192 "admin-node/web/icons/Icon-maskable-192.png"
Resize-Image $adminImg 512 512 "admin-node/web/icons/Icon-maskable-512.png"
Resize-Image $adminImg 64 64 "admin-node/web/favicon.png"

$adminImg.Dispose()
Write-Output "All icons successfully generated!"
