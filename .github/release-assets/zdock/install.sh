#!/usr/bin/env bash
set -euo pipefail

# Zdock 一键安装脚本（R2 发布通道）
#
#   curl -fsSL https://releases.73zls.com/zdock/install.sh | bash
#
# 可选环境变量：
#   ZDOCK_VERSION       指定版本，默认读取 latest.json
#   ZDOCK_RELEASE_BASE  覆盖下载根地址，默认 https://releases.73zls.com/zdock
#   ZDOCK_VARIANT       bundled（默认，内置 Node）| system（复用系统 Node 24+）
#   ZDOCK_INSTALL_DIR   macOS：App 安装目录（默认 /Applications）
#                       Linux：可执行入口目录（默认 ~/.local/bin）
#   ZDOCK_LINUX_FORMAT  Linux 安装方式：appimage（默认）| deb
#   ZDOCK_NO_OPEN       设为 1 时安装完成后不自动启动应用（仅 macOS）
#
# 注意：本脚本通常以 `curl | bash` 方式执行，stdin 是脚本内容本身，
# 因此任何步骤都不得读取 stdin（交互式命令必须带 -y / --non-interactive）。

BASE_URL="${ZDOCK_RELEASE_BASE:-https://releases.73zls.com/zdock}"
BASE_URL="${BASE_URL%/}"
VARIANT="${ZDOCK_VARIANT:-bundled}"

err() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m%s\033[0m\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || err "缺少依赖：$1"; }

case "$VARIANT" in
  bundled) PREFIX="Zdock" ;;
  system)  PREFIX="Zdock-System" ;;
  *)       err "ZDOCK_VARIANT 仅支持 bundled 或 system，当前：$VARIANT" ;;
esac

TMP_DIR="$(mktemp -d)"
MOUNT_POINT=""

cleanup() {
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need curl

VERSION="${ZDOCK_VERSION:-}"
if [ -z "$VERSION" ]; then
  manifest="$(curl -fsSL --retry 2 --connect-timeout 10 "$BASE_URL/latest.json" || true)"
  VERSION="$(printf '%s' "$manifest" \
    | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1)"
fi
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' \
  || err "无法确定版本号（latest.json 不可读或格式异常）"

# 从 latest.json 取指定资产的 sha256；取不到时输出空串（不阻断安装）。
asset_sha256() {
  command -v python3 >/dev/null 2>&1 || return 0
  curl -fsSL --retry 2 --connect-timeout 10 "$BASE_URL/latest.json" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    m = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in m.get("assets", []):
    if a.get("name") == sys.argv[1]:
        print(a.get("sha256", ""))
        break' "$1" 2>/dev/null || true
}

# download <asset-name> <destination>
download() {
  local asset="$1" dest="$2" expected actual
  info "下载 $asset"
  curl -fL --retry 2 --connect-timeout 10 "$BASE_URL/$asset" -o "$dest" \
    || err "下载失败：$BASE_URL/$asset"

  expected="$(asset_sha256 "$asset")"
  printf '%s' "$expected" | grep -Eq '^[0-9a-f]{64}$' || return 0
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$dest" | awk '{print tolower($1)}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$dest" | awk '{print tolower($1)}')"
  else
    return 0
  fi
  [ "$actual" = "$expected" ] || err "SHA-256 校验失败：$asset"
}

install_macos() {
  local arch suffix app_dir asset dmg
  need hdiutil

  arch="$(uname -m)"
  case "$arch" in
    arm64)  suffix="macos-arm64" ;;
    x86_64) suffix="macos-x64" ;;
    *)      err "不支持的 macOS 架构：$arch" ;;
  esac

  app_dir="${ZDOCK_INSTALL_DIR:-/Applications}"
  mkdir -p "$app_dir" || err "无法创建安装目录：$app_dir"
  [ -w "$app_dir" ] || err "$app_dir 不可写，请用管理员权限运行或设置 ZDOCK_INSTALL_DIR"

  asset="${PREFIX}-v${VERSION}-${suffix}.dmg"
  dmg="$TMP_DIR/Zdock.dmg"
  download "$asset" "$dmg"

  MOUNT_POINT="$(mktemp -d)"
  info "挂载安装包"
  hdiutil attach -nobrowse -quiet -mountpoint "$MOUNT_POINT" "$dmg" >/dev/null

  if [ ! -d "$MOUNT_POINT/Zdock.app" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    MOUNT_POINT=""
    err "安装包内未找到 Zdock.app"
  fi

  info "安装到 $app_dir/Zdock.app"
  rm -rf "$app_dir/Zdock.app"
  cp -R "$MOUNT_POINT/Zdock.app" "$app_dir/"
  hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  MOUNT_POINT=""

  info "已安装 Zdock v$VERSION"
  info "  应用路径：$app_dir/Zdock.app"

  if [ "${ZDOCK_NO_OPEN:-0}" != "1" ]; then
    open "$app_dir/Zdock.app"
  fi
}

install_linux_appimage() {
  local asset data_dir bin_dir
  asset="${PREFIX}-v${VERSION}-linux-x64.AppImage"
  data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Zdock"
  bin_dir="${ZDOCK_INSTALL_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"

  mkdir -p "$data_dir" "$bin_dir"
  download "$asset" "$data_dir/Zdock.AppImage"
  chmod +x "$data_dir/Zdock.AppImage"
  ln -sf "$data_dir/Zdock.AppImage" "$bin_dir/zdock"

  info "已安装 Zdock v$VERSION"
  info "  程序文件：$data_dir/Zdock.AppImage"
  info "  启动命令：$bin_dir/zdock"
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) info "提示：$bin_dir 不在 PATH 中，请加入 PATH 后使用 zdock 命令" ;;
  esac
}

install_linux_deb() {
  local asset deb
  need apt-get
  asset="${PREFIX}-v${VERSION}-linux-x64.deb"
  deb="$TMP_DIR/zdock.deb"
  download "$asset" "$deb"
  info "安装 deb 包（需要管理员权限）"
  sudo apt-get install -y "$deb" || err "deb 安装失败：$asset"
  info "已安装 Zdock v$VERSION"
}

install_linux() {
  local arch format
  arch="$(uname -m)"
  [ "$arch" = "x86_64" ] || err "暂不支持 Linux 架构：$arch（当前仅提供 x64）"

  format="${ZDOCK_LINUX_FORMAT:-appimage}"
  case "$format" in
    appimage) install_linux_appimage ;;
    deb)      install_linux_deb ;;
    *)        err "ZDOCK_LINUX_FORMAT 仅支持 appimage 或 deb，当前：$format" ;;
  esac
}

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *)      err "不支持的系统：$(uname -s)。Windows 请改用：irm $BASE_URL/install.ps1 | iex" ;;
esac
