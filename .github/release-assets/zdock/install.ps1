# Zdock 一键安装脚本（R2 发布通道）
#
#   irm https://releases.73zls.com/zdock/install.ps1 | iex
#
# 可选环境变量：
#   ZDOCK_VERSION       指定版本，默认读取 latest.json
#   ZDOCK_RELEASE_BASE  覆盖下载根地址，默认 https://releases.73zls.com/zdock
#   ZDOCK_VARIANT       bundled（默认，内置 Node）| system（复用系统 Node 24+）
#   ZDOCK_SILENT        设为 1 时静默安装（/S，不显示向导）
#   ZDOCK_NO_OPEN       设为 1 时安装完成后不自动启动应用
#
# 说明：本脚本以 `irm ... | iex` 方式执行，无法接收位置参数，
# 因此全部配置通过环境变量传入。

$ErrorActionPreference = 'Stop'

$baseUrl = if ($env:ZDOCK_RELEASE_BASE) { $env:ZDOCK_RELEASE_BASE.TrimEnd('/') } else { 'https://releases.73zls.com/zdock' }
$variant = if ($env:ZDOCK_VARIANT) { $env:ZDOCK_VARIANT } else { 'bundled' }

switch ($variant) {
  'bundled' { $prefix = 'Zdock' }
  'system'  { $prefix = 'Zdock-System' }
  default   { throw "ZDOCK_VARIANT 仅支持 bundled 或 system，当前：$variant" }
}

Write-Host "读取发布清单 $baseUrl/latest.json"
$manifest = Invoke-RestMethod -Uri "$baseUrl/latest.json"

$version = if ($env:ZDOCK_VERSION) { $env:ZDOCK_VERSION } else { "$($manifest.version)" }
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$') {
  throw "无法确定版本号：$version"
}

if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
  Write-Warning '当前仅提供 Windows x64 安装包，ARM64 设备将以仿真方式运行。'
}

$asset = "$prefix-v$version-windows-x64-setup.exe"
$url = "$baseUrl/$asset"

$tmpDir = Join-Path $env:TEMP ("zdock-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$installer = Join-Path $tmpDir $asset

try {
  Write-Host "下载 $asset"
  Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

  $entry = $manifest.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1
  if ($entry -and $entry.sha256) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $installer).Hash.ToLower()
    if ($actual -ne "$($entry.sha256)".ToLower()) {
      throw "SHA-256 校验失败：$asset"
    }
  }

  if ($env:ZDOCK_SILENT -eq '1') {
    Write-Host "静默安装 Zdock v$version"
    $proc = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
  } else {
    Write-Host "运行安装程序 Zdock v$version（按向导完成安装）"
    $proc = Start-Process -FilePath $installer -Wait -PassThru
  }

  if ($proc.ExitCode -ne 0) {
    throw "安装程序退出码 $($proc.ExitCode)"
  }

  Write-Host "已安装 Zdock v$version（当前用户，无需管理员）"

  if ($env:ZDOCK_NO_OPEN -ne '1') {
    $exe = Join-Path $env:LOCALAPPDATA 'Zdock\Zdock.exe'
    if (Test-Path $exe) {
      Start-Process -FilePath $exe | Out-Null
    } else {
      Write-Host '可从开始菜单启动 Zdock'
    }
  }
} finally {
  Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
