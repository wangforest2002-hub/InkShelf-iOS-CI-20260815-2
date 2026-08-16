[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UnsignedIpa,

    [Parameter(Mandatory = $true)]
    [string]$CertificateZip,

    [Parameter(Mandatory = $true)]
    [string]$ZSign,

    [Parameter(Mandatory = $true)]
    [string]$OutputIpa
)

$ErrorActionPreference = "Stop"
$inputPath = (Resolve-Path -LiteralPath $UnsignedIpa).Path
$certificatePath = (Resolve-Path -LiteralPath $CertificateZip).Path
$signerPath = (Resolve-Path -LiteralPath $ZSign).Path
$outputPath = [IO.Path]::GetFullPath($OutputIpa)

if (Test-Path -LiteralPath $outputPath) {
    throw "输出 IPA 已存在，请换一个文件名，避免意外覆盖。"
}

$temporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("inkshelf-local-sign-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
    Expand-Archive -LiteralPath $certificatePath -DestinationPath $temporaryRoot
    $p12 = Get-ChildItem -LiteralPath $temporaryRoot -Filter *.p12 -Recurse | Select-Object -First 1
    $profile = Get-ChildItem -LiteralPath $temporaryRoot -Filter *.mobileprovision -Recurse | Select-Object -First 1
    $passwordFile = Get-ChildItem -LiteralPath $temporaryRoot -Filter *.txt -Recurse | Select-Object -First 1
    if ($null -eq $p12 -or $null -eq $profile -or $null -eq $passwordFile) {
        throw "证书包缺少 p12、mobileprovision 或密码说明。"
    }

    $passwordText = (Get-Content -Raw -LiteralPath $passwordFile.FullName).Trim()
    $password = ($passwordText -split "[:：]", 2)[-1].Trim()
    if ([string]::IsNullOrWhiteSpace($password)) {
        throw "无法从证书说明中读取签名密码。"
    }

    & $signerPath `
        -f `
        -k $p12.FullName `
        -p $password `
        -m $profile.FullName `
        -o $outputPath `
        $inputPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
        throw "IPA 签名失败。"
    }
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporaryRoot = (Resolve-Path -LiteralPath $temporaryRoot).Path
        $systemTemporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $safeName = [IO.Path]::GetFileName($resolvedTemporaryRoot).StartsWith(
            "inkshelf-local-sign-",
            [StringComparison]::Ordinal
        )
        if (-not $resolvedTemporaryRoot.StartsWith(
            $systemTemporaryRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -or -not $safeName) {
            throw "拒绝清理不安全的临时目录：$resolvedTemporaryRoot"
        }
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

$file = Get-Item -LiteralPath $outputPath
[pscustomobject]@{
    File = $file.FullName
    Size = $file.Length
    SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
}
