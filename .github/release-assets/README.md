# Zdock 安装 / 下载

本目录是 Zdock 的官方发布页。每个版本包含 macOS / Windows / Linux 安装包和一个
`latest.json` 清单：

- `latest.json`：最新版本号、各平台文件名、大小、SHA-256 与下载地址
- `Zdock-v{version}-*.dmg`：macOS 安装包（Apple Silicon / Intel）
- `Zdock-v{version}-windows-x64-setup.exe`：Windows x64 安装程序
- `Zdock-v{version}-linux-x64.AppImage` / `.deb`：Linux x64 安装包

下载根地址：<https://releases.73zls.com/zdock>

## 两种构建

每个平台都提供两种构建，按需选择：

- **内置 Node（`Zdock-v{version}-*`，推荐）**：自带 Node 运行时，开箱即用，是默认下载。
- **系统 Node（`Zdock-System-v{version}-*`）**：体积更小，复用系统上已安装的 Node 24+；
  缺少 Node 24 时应用会先显示安装配置界面。

以下命令默认下载**内置 Node**版本；如需系统版，把文件名里的 `Zdock-v` 换成
`Zdock-System-v` 即可。

## 一键安装 / 更新

以下命令都会先读取 `latest.json` 获取最新版本，再按当前系统架构下载对应安装包。

### macOS

```bash
set -euo pipefail
arch="$(uname -m)"
case "$arch" in
  arm64) target="macos-arm64" ;;
  x86_64) target="macos-x64" ;;
  *) echo "不支持的 macOS 架构：$arch" >&2; exit 1 ;;
esac
version="$(curl -fsSL https://releases.73zls.com/zdock/latest.json | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1)"
dmg="$(mktemp -d)/Zdock.dmg"
curl -fL "https://releases.73zls.com/zdock/Zdock-v${version}-${target}.dmg" -o "$dmg"
mount_point="$(mktemp -d)"
hdiutil attach -nobrowse -quiet -mountpoint "$mount_point" "$dmg"
rm -rf "/Applications/Zdock.app"
cp -R "$mount_point/Zdock.app" /Applications/
hdiutil detach "$mount_point" -quiet
open /Applications/Zdock.app
```

默认安装到 `/Applications/Zdock.app`。安装包已签名并公证；若系统仍拦截，可执行
`sudo xattr -cr /Applications/Zdock.app` 后重试。

### Windows PowerShell

```powershell
$version = (Invoke-RestMethod 'https://releases.73zls.com/zdock/latest.json').version
$url = "https://releases.73zls.com/zdock/Zdock-v$version-windows-x64-setup.exe"
$installer = Join-Path $env:TEMP "Zdock-setup.exe"
Invoke-WebRequest $url -OutFile $installer
Start-Process $installer -Wait
```

安装程序为当前用户安装（无需管理员）。

> Windows 安装包未做代码签名，SmartScreen 可能提示"未知发布者"，选择"仍要运行"即可。

### Linux

AppImage（免安装，直接运行）：

```bash
set -euo pipefail
version="$(curl -fsSL https://releases.73zls.com/zdock/latest.json | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1)"
dir="${XDG_DATA_HOME:-$HOME/.local/share}/Zdock"
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$dir" "$bin_dir"
curl -fL "https://releases.73zls.com/zdock/Zdock-v${version}-linux-x64.AppImage" -o "$dir/Zdock.AppImage"
chmod +x "$dir/Zdock.AppImage"
ln -sf "$dir/Zdock.AppImage" "$bin_dir/zdock"
echo "启动命令：$bin_dir/zdock"
```

deb（Debian / Ubuntu）：

```bash
version="$(curl -fsSL https://releases.73zls.com/zdock/latest.json | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1)"
curl -fL "https://releases.73zls.com/zdock/Zdock-v${version}-linux-x64.deb" -o /tmp/zdock.deb
sudo apt-get install -y /tmp/zdock.deb
```

Linux 版需要 `libwebkit2gtk-4.1` 等运行库。

## 手动下载

也可以按文件名直接下载对应平台的安装包：

| 平台 | 架构 | 内置 Node（推荐） | 系统 Node |
| --- | --- | --- | --- |
| macOS | Apple Silicon | `Zdock-v{version}-macos-arm64.dmg` | `Zdock-System-v{version}-macos-arm64.dmg` |
| macOS | Intel | `Zdock-v{version}-macos-x64.dmg` | `Zdock-System-v{version}-macos-x64.dmg` |
| Windows | x64 | `Zdock-v{version}-windows-x64-setup.exe` | `Zdock-System-v{version}-windows-x64-setup.exe` |
| Linux | x64 | `Zdock-v{version}-linux-x64.AppImage` | `Zdock-System-v{version}-linux-x64.AppImage` |
| Linux | x64 | `Zdock-v{version}-linux-x64.deb` | `Zdock-System-v{version}-linux-x64.deb` |

下载后可对照 `latest.json` 中的 `sha256` 校验文件完整性：

```bash
curl -fsSL https://releases.73zls.com/zdock/latest.json | \
  python3 -c 'import json,sys; [print(a["sha256"], a["name"]) for a in json.load(sys.stdin)["assets"]]'
```
