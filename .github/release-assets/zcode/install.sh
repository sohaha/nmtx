#!/usr/bin/env bash
set -euo pipefail

# zcode one-line installer (R2 release channel):
#   curl -fsSL https://releases.73zls.com/zcode/install.sh | bash
#
# Optional env:
#   ZCODE_VERSION      install a specific version (default: latest.json)
#   ZCODE_RELEASE_BASE override the download base URL
#   ZCODE_INSTALL_DIR  override the launcher directory (default: ~/.local/bin)

BASE_URL="${ZCODE_RELEASE_BASE:-https://releases.73zls.com/zcode}"
BIN_DIR="${ZCODE_INSTALL_DIR:-$HOME/.local/bin}"

err() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m%s\033[0m\n' "$*"; }

command -v curl >/dev/null 2>&1 || err "需要 curl"
command -v unzip >/dev/null 2>&1 || err "需要 unzip（解压 release ZIP）"

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Darwin)
    case "$ARCH" in
      arm64)  TARGET="aarch64-apple-darwin" ;;
      x86_64) TARGET="x86_64-apple-darwin" ;;
      *)      err "不支持的 macOS 架构：$ARCH" ;;
    esac
    ;;
  Linux)
    case "$ARCH" in
      x86_64)        TARGET="x86_64-unknown-linux-gnu" ;;
      aarch64|arm64) TARGET="aarch64-unknown-linux-gnu" ;;
      *)             err "不支持的 Linux 架构：$ARCH" ;;
    esac
    ;;
  *)
    err "不支持的操作系统：$OS（Windows 请用 README 里的 PowerShell 命令）"
    ;;
esac

VERSION="${ZCODE_VERSION:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(curl -fsSL --retry 2 --connect-timeout 10 "$BASE_URL/latest.json" \
    | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1)"
fi
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' \
  || err "无法确定版本号"

ASSET="zcode-v${VERSION}-${TARGET}.zip"
info "下载 zcode v${VERSION} (${TARGET})"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl -fL --retry 2 "$BASE_URL/$ASSET" -o "$tmpdir/$ASSET" \
  || err "下载失败：$BASE_URL/$ASSET"

# 校验 SHA-256（latest.json 中有对应记录时才校验）
EXPECTED="$(curl -fsSL --retry 2 --connect-timeout 10 "$BASE_URL/latest.json" 2>/dev/null \
  | python3 -c 'import json,sys
try:
    m = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in m.get("assets", []):
    if a.get("name") == "'"$ASSET"'":
        print(a.get("sha256", ""))
        break' 2>/dev/null || true)"
if printf '%s' "$EXPECTED" | grep -Eq '^[0-9a-f]{64}$'; then
  if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "$tmpdir/$ASSET" | awk '{print tolower($1)}')"
  elif command -v shasum >/dev/null 2>&1; then
    ACTUAL="$(shasum -a 256 "$tmpdir/$ASSET" | awk '{print tolower($1)}')"
  else
    ACTUAL=""
  fi
  if [ -n "$ACTUAL" ] && [ "$ACTUAL" != "$EXPECTED" ]; then
    err "SHA-256 校验失败：$ASSET"
  fi
fi

INSTALL_DIR="${ZCODE_HOME:-$HOME/.zcode}/builds/versions/${VERSION}"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
unzip -q -o "$tmpdir/$ASSET" -d "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/zcode" 2>/dev/null || true

ln -sf "$INSTALL_DIR/zcode" "$BIN_DIR/zcode"

info "已安装 zcode v${VERSION}"
info "  程序目录：$INSTALL_DIR"
info "  启动命令：$BIN_DIR/zcode"
"$BIN_DIR/zcode" --version 2>/dev/null | head -n 1 || true
