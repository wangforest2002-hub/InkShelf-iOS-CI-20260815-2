[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SignedIpa,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [int]$Build,

    [string]$Title = "二次元小家有新布置",

    [string[]]$Notes = @("体验优化与问题修复"),

    [switch]$Mandatory
)

$ErrorActionPreference = "Stop"
$bundleIdentifier = "com.inkshelf.reader"
$server = "document-center-thailand"
$remoteRoot = "/srv/inkshelf-update/public"
$remoteStage = "/home/admin/inkshelf-update-publish"
$baseURL = "https://4-3rail.top/inkshelf-update"
$resolvedIpa = (Resolve-Path -LiteralPath $SignedIpa).Path

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolvedIpa)
try {
    $names = @($archive.Entries | ForEach-Object FullName)
    if (-not ($names -match '^Payload/[^/]+\.app/_CodeSignature/CodeResources$')) {
        throw "IPA 没有代码签名，请先用原证书签名。"
    }
    if (-not ($names -match '^Payload/[^/]+\.app/embedded\.mobileprovision$')) {
        throw "IPA 没有内嵌描述文件，无法在线安装。"
    }
} finally {
    $archive.Dispose()
}

$releaseName = "InkShelf-$Version-$Build"
$ipaName = "$releaseName.ipa"
$manifestName = "$releaseName.plist"
$ipaURL = "$baseURL/releases/$ipaName"
$manifestURL = "$baseURL/releases/$manifestName"
$installURL = "itms-services://?action=download-manifest&url=$([Uri]::EscapeDataString($manifestURL))"
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedIpa).Hash
$size = (Get-Item -LiteralPath $resolvedIpa).Length
$publishRoot = Join-Path ([IO.Path]::GetTempPath()) ("inkshelf-release-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $publishRoot | Out-Null

try {
    $stagedIpa = Join-Path $publishRoot $ipaName
    $stagedManifest = Join-Path $publishRoot $manifestName
    $stagedLatest = Join-Path $publishRoot "latest.json.next"
    Copy-Item -LiteralPath $resolvedIpa -Destination $stagedIpa

    $escapedIpaURL = [Security.SecurityElement]::Escape($ipaURL)
    $escapedBundleID = [Security.SecurityElement]::Escape($bundleIdentifier)
    $escapedVersion = [Security.SecurityElement]::Escape($Version)
    $manifest = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>$escapedIpaURL</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>$escapedBundleID</string>
        <key>bundle-version</key><string>$escapedVersion</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>二次元小家</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
"@
    Set-Content -LiteralPath $stagedManifest -Value $manifest -Encoding utf8NoBOM

    $latest = [ordered]@{
        schema = 1
        version = $Version
        build = $Build
        minimum_ios = "18.0"
        published_at = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")
        title = $Title
        notes = @($Notes)
        mandatory = [bool]$Mandatory
        bundle_identifier = $bundleIdentifier
        package_size = $size
        sha256 = $hash
        install_url = $installURL
        data_policy = "preserve_app_container"
    }
    $latest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stagedLatest -Encoding utf8NoBOM

    ssh $server "mkdir -p '$remoteStage'"
    scp $stagedIpa "${server}:$remoteStage/$ipaName"
    scp $stagedManifest "${server}:$remoteStage/$manifestName"
    scp $stagedLatest "${server}:$remoteStage/latest.json.next"
    ssh $server "sudo -n mkdir -p '$remoteRoot/releases' && sudo -n install -m 644 '$remoteStage/$ipaName' '$remoteRoot/releases/$ipaName' && sudo -n install -m 644 '$remoteStage/$manifestName' '$remoteRoot/releases/$manifestName' && sudo -n install -m 644 '$remoteStage/latest.json.next' '$remoteRoot/latest.json.next' && sudo -n mv '$remoteRoot/latest.json.next' '$remoteRoot/latest.json'"

    $published = Invoke-RestMethod -Uri "$baseURL/latest.json" -Headers @{ "Cache-Control" = "no-cache" }
    if ($published.build -ne $Build -or $published.sha256 -ne $hash) {
        throw "服务器发布校验失败。"
    }
    Write-Host "发布成功：$Version ($Build)"
    Write-Host "安装页：$baseURL/"
    Write-Host "SHA256：$hash"
} finally {
    if (Test-Path -LiteralPath $publishRoot) {
        $resolvedTemp = (Resolve-Path -LiteralPath $publishRoot).Path
        if (-not $resolvedTemp.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
            throw "拒绝清理非临时目录：$resolvedTemp"
        }
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
