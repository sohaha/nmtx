# zuno one-line installer (R2 release channel), Windows PowerShell:
#   irm https://releases.73zls.com/zuno/install.ps1 | iex
#
# Optional env:
#   ZUNO_VERSION       install a specific version (default: latest.json)
#   ZUNO_RELEASE_BASE  override the download base URL
#   ZUNO_INSTALL_DIR   override the launcher directory (default: ~\.zuno\bin)

$ErrorActionPreference = 'Stop'

$BaseUrl    = if ($env:ZUNO_RELEASE_BASE) { $env:ZUNO_RELEASE_BASE } else { 'https://releases.73zls.com/zuno' }
$InstallDir = if ($env:ZUNO_INSTALL_DIR)  { $env:ZUNO_INSTALL_DIR  } else { Join-Path $env:LOCALAPPDATA 'zuno\bin' }
# Keep the builds root aligned with crates/zuno-build-support/src/storage_helpers.rs:
# ZUNO_HOME (when set) wins, otherwise %LOCALAPPDATA%\zuno\builds on Windows.
$BuildsRoot = if ($env:ZUNO_HOME)         { Join-Path $env:ZUNO_HOME 'builds' } else { Join-Path $env:LOCALAPPDATA 'zuno\builds' }

function Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Err($msg)  { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

# Resolve target
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
switch ($arch) {
  'X64'   { $Target = 'x86_64-pc-windows-msvc' }
  'Arm64' { $Target = 'aarch64-pc-windows-msvc' }
  default { Err "unsupported Windows architecture: $arch" }
}

# Resolve version
$Version = $env:ZUNO_VERSION
if (-not $Version) {
  try {
    $manifest = Invoke-RestMethod -Uri "$BaseUrl/latest.json" -TimeoutSec 15
    $Version  = $manifest.version
  } catch {
    Err "failed to fetch $BaseUrl/latest.json : $_"
  }
}
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$') {
  Err "could not determine version"
}

$Asset = "zuno-v$Version-$Target.zip"
Info "downloading zuno v$Version ($Target)"

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("zuno-install-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
try {
  $ZipPath = Join-Path $TmpDir $Asset
  try {
    Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $ZipPath -UseBasicParsing
  } catch {
    Err "download failed: $BaseUrl/$Asset : $_"
  }

  # Optional SHA-256 verification against latest.json
  try {
    $manifest = Invoke-RestMethod -Uri "$BaseUrl/latest.json" -TimeoutSec 15
    $expected = ($manifest.assets | Where-Object { $_.name -eq $Asset } | Select-Object -First 1).sha256
    if ($expected) {
      $actual = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLower()
      if ($actual -ne $expected.ToLower()) {
        Err "SHA-256 mismatch for $Asset"
      }
    }
  } catch {
    # latest.json lookup is best-effort; proceed without verification
  }

  $InstallVersionDir = Join-Path $BuildsRoot "versions\$Version"
  New-Item -ItemType Directory -Path $InstallVersionDir -Force | Out-Null
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

  Expand-Archive -Path $ZipPath -DestinationPath $InstallVersionDir -Force

  $Binary = Join-Path $InstallVersionDir 'zuno.exe'
  if (-not (Test-Path $Binary)) {
    # Some zips nest a top-level folder; fall back to the first zuno.exe
    $Binary = Get-ChildItem -Path $InstallVersionDir -Recurse -Filter 'zuno.exe' | Select-Object -First 1 -ExpandProperty FullName
    if (-not $Binary) { Err "zuno.exe not found inside $Asset" }
  }

  $Launcher = Join-Path $InstallDir 'zuno.exe'
  Copy-Item -Path $Binary -Destination $Launcher -Force

  Info "installed zuno v$Version"
  Info "  launcher: $Launcher"
  Info "  add to PATH if needed: $InstallDir"

  try { & $Launcher --version | Select-Object -First 1 } catch {}
} finally {
  Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
