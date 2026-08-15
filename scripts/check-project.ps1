param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$required = @(
    'project.yml',
    'InkShelf\App\InkShelfApp.swift',
    'InkShelf\Store\LibraryStore.swift',
    'InkShelf\Views\Reader\PDFKitReaderView.swift',
    'InkShelf\Views\Reader\ImagePagerView.swift',
    'InkShelf\Resources\Assets.xcassets\AppIcon.appiconset\AppIcon-1024.png'
)

foreach ($relativePath in $required) {
    $path = Join-Path $ProjectRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $relativePath"
    }
    if ((Get-Item -LiteralPath $path).Length -eq 0) {
        throw "Required file is empty: $relativePath"
    }
}

$jsonFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'InkShelf\Resources\Assets.xcassets') -Filter Contents.json -Recurse
foreach ($file in $jsonFiles) {
    Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json | Out-Null
}

[xml](Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'InkShelf\Resources\Info.plist')) | Out-Null

$swiftFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'InkShelf') -Filter *.swift -Recurse
$todoMarkers = $swiftFiles | Select-String -Pattern 'TODO|FIXME|fatalError\("TODO' -CaseSensitive
if ($todoMarkers) {
    throw "Unresolved TODO/FIXME marker found."
}

$totalLines = ($swiftFiles | Get-Content | Measure-Object -Line).Lines
Write-Output "Project check passed: $($swiftFiles.Count) Swift files, $totalLines lines, $($jsonFiles.Count) asset manifests."

