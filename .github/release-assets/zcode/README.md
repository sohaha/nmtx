# zcode 安装 / 下载

本目录是 zcode 的官方发布页。每个版本包含 6 个平台的 ZIP 包和一个 `latest.json` 清单：

- `latest.json`：最新版本号、各平台文件名、大小、SHA-256 与下载地址
- `zcode-v{version}-{target}.zip`：对应平台的二进制压缩包

下载根地址：<https://releases.73zls.com/zcode>

## 一键安装 / 更新（macOS / Linux）

```bash
curl -fsSL https://releases.73zls.com/zcode/install.sh | bash
```

安装脚本会读取 `latest.json` 获取最新版本，按当前系统架构下载对应 ZIP，
解压到 `~/.zcode/builds/versions/{version}/`，并在 `~/.local/bin/zcode`
创建启动入口。

可选环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ZCODE_VERSION` | latest.json | 安装指定版本 |
| `ZCODE_RELEASE_BASE` | `https://releases.73zls.com/zcode` | 覆盖下载源 |
| `ZCODE_INSTALL_DIR` | `~/.local/bin` | 启动入口目录 |

### Windows PowerShell

```powershell
$target = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
$version = (Invoke-RestMethod 'https://releases.73zls.com/zcode/latest.json').version
$url = "https://releases.73zls.com/zcode/zcode-v$version-$target.zip"
$tmp = Join-Path $env:TEMP ("zcode-" + [guid]::NewGuid())
$zip = Join-Path $tmp 'zcode.zip'
$dest = Join-Path $env:LOCALAPPDATA "zcode\builds\versions\$version"
$binDir = Join-Path $env:LOCALAPPDATA 'zcode\bin'
New-Item -ItemType Directory -Force -Path $tmp, $dest, $binDir | Out-Null
Invoke-WebRequest $url -OutFile $zip
Expand-Archive $zip -DestinationPath $dest -Force
Copy-Item (Join-Path $dest 'zcode.exe') (Join-Path $binDir 'zcode.exe') -Force
& (Join-Path $binDir 'zcode.exe') --version
```

默认安装到 `%LOCALAPPDATA%\zcode\builds\versions\{version}`，可执行入口在
`%LOCALAPPDATA%\zcode\bin\zcode.exe`（请把该目录加入 PATH）。

> Windows 二进制未做代码签名，SmartScreen 可能提示“未知发布者”，选择“仍要运行”即可。

## 手动下载

也可以直接按文件名下载对应平台的 ZIP：

| 平台 | 架构 | 文件名 |
| --- | --- | --- |
| macOS | Apple Silicon | `zcode-v{version}-aarch64-apple-darwin.zip` |
| macOS | Intel | `zcode-v{version}-x86_64-apple-darwin.zip` |
| Linux | x64 | `zcode-v{version}-x86_64-unknown-linux-gnu.zip` |
| Linux | ARM64 | `zcode-v{version}-aarch64-unknown-linux-gnu.zip` |
| Windows | x64 | `zcode-v{version}-x86_64-pc-windows-msvc.zip` |
| Windows | ARM64 | `zcode-v{version}-aarch64-pc-windows-msvc.zip` |

Linux x64 包基于 manylinux2014（glibc 2.17）构建并内置 OpenSSL 运行库，
在老发行版上也能运行；解压后把整个目录放在同一位置，运行其中的 `zcode`
启动脚本即可。

下载后可对照 `latest.json` 中的 `sha256` 校验文件完整性：

```bash
curl -fsSL https://releases.73zls.com/zcode/latest.json | \
  python3 -c 'import json,sys; [print(a["sha256"], a["name"]) for a in json.load(sys.stdin)["assets"]]'
```

## License

与源码仓库一致，见 <https://cnb.cool/zls_nmtx/sohaha/zcode>。
