# Zdock 安装 / 下载

本目录是 Zdock 的官方发布页。每个版本包含 macOS / Windows / Linux 安装包、一键安装脚本
和一个 `latest.json` 清单：

- `latest.json`：最新版本号、各平台文件名、大小、SHA-256 与下载地址
- `install.sh`：macOS / Linux 一键安装脚本
- `install.ps1`：Windows 一键安装脚本
- `Zdock-v{version}-macos-*.dmg`：macOS 安装包（Apple Silicon / Intel）
- `Zdock-v{version}-windows-x64-setup.exe`：Windows x64 安装程序
- `Zdock-v{version}-linux-x64.AppImage` / `.deb`：Linux x64 安装包

下载根地址：<https://releases.73zls.com/zdock>

## 一键安装 / 更新

### macOS / Linux

```bash
curl -fsSL https://releases.73zls.com/zdock/install.sh | bash
```

### Windows PowerShell

```powershell
irm https://releases.73zls.com/zdock/install.ps1 | iex
```

两个脚本都会先读取 `latest.json` 获取最新版本，按当前系统架构选择对应安装包，
并在安装前用清单里的 `sha256` 校验下载文件。

## 两种构建

每个平台都提供两种构建，按需选择：

- **内置 Node（`Zdock-v{version}-*`，推荐）**：自带 Node 运行时，开箱即用，是默认下载。
- **系统 Node（`Zdock-System-v{version}-*`）**：体积更小，复用系统上已安装的 Node 24+；
  缺少 Node 24 时应用会先显示安装配置界面。

上面的命令默认安装**内置 Node**版本。安装系统版请把 `ZDOCK_VARIANT` 设为 `system`：

```bash
export ZDOCK_VARIANT=system
curl -fsSL https://releases.73zls.com/zdock/install.sh | bash
```

```powershell
$env:ZDOCK_VARIANT = 'system'
irm https://releases.73zls.com/zdock/install.ps1 | iex
```

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ZDOCK_VERSION` | `latest.json` | 安装指定版本 |
| `ZDOCK_RELEASE_BASE` | `https://releases.73zls.com/zdock` | 覆盖下载源 |
| `ZDOCK_VARIANT` | `bundled` | `bundled`（内置 Node）或 `system`（系统 Node） |
| `ZDOCK_INSTALL_DIR` | macOS `/Applications`；Linux `~/.local/bin` | 安装目录 |
| `ZDOCK_LINUX_FORMAT` | `appimage` | Linux 安装方式：`appimage` 或 `deb` |
| `ZDOCK_SILENT` | 未设置 | Windows：设为 `1` 时静默安装（`/S`） |
| `ZDOCK_NO_OPEN` | 未设置 | 设为 `1` 时安装完成后不自动启动应用（macOS） |

安装到自定义目录（macOS）：

```bash
export ZDOCK_INSTALL_DIR="$HOME/Applications"
curl -fsSL https://releases.73zls.com/zdock/install.sh | bash
```

## 各平台安装行为

### macOS

安装到 `/Applications/Zdock.app` 并自动启动。安装包已签名并公证；若系统仍拦截，可执行
`sudo xattr -cr /Applications/Zdock.app` 后重试。

### Windows

安装程序为当前用户安装（无需管理员），默认位置 `%LOCALAPPDATA%\Zdock`。
不加 `ZDOCK_SILENT` 时会弹出安装向导；加 `ZDOCK_SILENT=1` 则静默安装。

> Windows 安装包未做代码签名，SmartScreen 可能提示“未知发布者”，选择“仍要运行”即可。

### Linux

AppImage 免安装：下载到 `~/.local/share/Zdock/Zdock.AppImage`，并在 `~/.local/bin/zdock`
创建启动入口。改用 deb 安装请设置 `ZDOCK_LINUX_FORMAT=deb`（需要管理员权限）。

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
