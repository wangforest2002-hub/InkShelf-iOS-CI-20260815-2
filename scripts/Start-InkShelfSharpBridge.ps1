[CmdletBinding()]
param(
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
$bridge = Join-Path $PSScriptRoot "inkshelf_sharp_bridge.py"
$entry = "C:\Users\wzm44\Documents\Codex\2026-05-24\new-chat-6\batch_good_anime_model.ps1"
$pythonCandidates = @(
    "C:\Users\wzm44\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe",
    (Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) {
    throw "缺少电脑桥程序：$bridge"
}
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) {
    throw "缺少指定 Sharp 入口：$entry"
}
if ($pythonCandidates.Count -eq 0) {
    throw "没有找到 Python 运行环境。"
}

$localAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
    Select-Object -ExpandProperty IPAddress -Unique

Write-Host "二次元小家 Sharp 图片清晰化电脑桥"
Write-Host "固定方案：realesrgan-x4plus-anime 4x -> Lanczos 2x -> PNG"
Write-Host "请在 iPad 的 设置 -> Sharp 图片清晰化 中填写："
foreach ($address in $localAddresses) {
    Write-Host "  http://${address}:$Port"
}
Write-Host ""
Write-Host "保持此窗口开启即可处理 iPad 发来的图片。按 Ctrl+C 停止。"

& $pythonCandidates[0] $bridge --entry $entry --port $Port
exit $LASTEXITCODE

