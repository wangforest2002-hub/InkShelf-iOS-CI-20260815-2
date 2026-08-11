param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Add-Type -AssemblyName System.Drawing

$iconDirectory = Join-Path $ProjectRoot 'InkShelf\Resources\Assets.xcassets\AppIcon.appiconset'
New-Item -ItemType Directory -Force -Path $iconDirectory | Out-Null

function New-InkShelfIcon {
    param(
        [string]$Path,
        [System.Drawing.Color]$TopColor,
        [System.Drawing.Color]$BottomColor,
        [System.Drawing.Color]$PageColor,
        [System.Drawing.Color]$AccentColor,
        [bool]$Monochrome = $false
    )

    $bitmap = New-Object System.Drawing.Bitmap 1024, 1024
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    $rectangle = New-Object System.Drawing.Rectangle 0, 0, 1024, 1024
    $background = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rectangle, $TopColor, $BottomColor, 45
    $graphics.FillRectangle($background, $rectangle)

    $glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(42, $AccentColor))
    $graphics.FillEllipse($glow, 170, 120, 684, 684)

    $starBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, $PageColor))
    foreach ($star in @(@(224,220,12), @(804,288,9), @(744,166,15), @(178,420,8), @(850,500,11))) {
        $graphics.FillEllipse($starBrush, $star[0], $star[1], $star[2], $star[2])
    }

    $leftPage = New-Object System.Drawing.Drawing2D.GraphicsPath
    $leftPage.StartFigure()
    $leftPage.AddBezier(180, 450, 285, 405, 405, 430, 503, 515)
    $leftPage.AddBezier(503, 515, 492, 640, 490, 736, 495, 824)
    $leftPage.AddBezier(495, 824, 390, 747, 282, 724, 188, 759)
    $leftPage.AddBezier(188, 759, 184, 660, 181, 552, 180, 450)
    $leftPage.CloseFigure()

    $rightPage = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rightPage.StartFigure()
    $rightPage.AddBezier(844, 450, 739, 405, 619, 430, 521, 515)
    $rightPage.AddBezier(521, 515, 532, 640, 534, 736, 529, 824)
    $rightPage.AddBezier(529, 824, 634, 747, 742, 724, 836, 759)
    $rightPage.AddBezier(836, 759, 840, 660, 843, 552, 844, 450)
    $rightPage.CloseFigure()

    $pageBrush = New-Object System.Drawing.SolidBrush $PageColor
    $graphics.FillPath($pageBrush, $leftPage)
    $graphics.FillPath($pageBrush, $rightPage)

    $lineColor = if ($Monochrome) { [System.Drawing.Color]::FromArgb(160, 38, 38, 48) } else { [System.Drawing.Color]::FromArgb(130, 82, 58, 180) }
    $linePen = New-Object System.Drawing.Pen $lineColor, 12
    $linePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $linePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawBezier($linePen, 503, 515, 507, 630, 510, 735, 512, 822)
    $graphics.DrawBezier($linePen, 282, 520, 356, 500, 420, 525, 470, 570)
    $graphics.DrawBezier($linePen, 742, 520, 668, 500, 604, 525, 554, 570)

    $accentBrush = New-Object System.Drawing.SolidBrush $AccentColor
    $petal = New-Object System.Drawing.Drawing2D.GraphicsPath
    $petal.AddBezier(726, 342, 765, 301, 819, 324, 806, 373)
    $petal.AddBezier(806, 373, 790, 421, 734, 410, 726, 342)
    $petal.CloseFigure()
    $graphics.FillPath($accentBrush, $petal)

    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)

    $accentBrush.Dispose()
    $petal.Dispose()
    $linePen.Dispose()
    $pageBrush.Dispose()
    $rightPage.Dispose()
    $leftPage.Dispose()
    $starBrush.Dispose()
    $glow.Dispose()
    $background.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

New-InkShelfIcon `
    -Path (Join-Path $iconDirectory 'AppIcon-1024.png') `
    -TopColor ([System.Drawing.Color]::FromArgb(255, 54, 159, 225)) `
    -BottomColor ([System.Drawing.Color]::FromArgb(255, 139, 91, 220)) `
    -PageColor ([System.Drawing.Color]::FromArgb(255, 226, 246, 255)) `
    -AccentColor ([System.Drawing.Color]::FromArgb(255, 255, 101, 142))

New-InkShelfIcon `
    -Path (Join-Path $iconDirectory 'AppIcon-1024-dark.png') `
    -TopColor ([System.Drawing.Color]::FromArgb(255, 7, 5, 28)) `
    -BottomColor ([System.Drawing.Color]::FromArgb(255, 38, 20, 86)) `
    -PageColor ([System.Drawing.Color]::FromArgb(255, 186, 232, 255)) `
    -AccentColor ([System.Drawing.Color]::FromArgb(255, 245, 87, 139))

New-InkShelfIcon `
    -Path (Join-Path $iconDirectory 'AppIcon-1024-tinted.png') `
    -TopColor ([System.Drawing.Color]::FromArgb(255, 225, 225, 230)) `
    -BottomColor ([System.Drawing.Color]::FromArgb(255, 122, 122, 134)) `
    -PageColor ([System.Drawing.Color]::FromArgb(255, 250, 250, 252)) `
    -AccentColor ([System.Drawing.Color]::FromArgb(255, 55, 55, 65)) `
    -Monochrome $true

Write-Output "Generated app icons in $iconDirectory"
