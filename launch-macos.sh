#!/bin/bash
set -u

REPOSITORY="qq541253643-art/seamless-collage-tool"
BRANCH="main"
RESOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_PATH="$RESOURCE_DIR/app.html"
STATUS_PATH="$RESOURCE_DIR/update-status.txt"
VERSION_PATH="$RESOURCE_DIR/version.txt"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/seamless-collage-update.XXXXXX")"
NO_OPEN=0
if [ "${1:-}" = "--no-open" ]; then
  NO_OPEN=1
fi

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

write_status() {
  {
    date '+%Y-%m-%d %H:%M:%S'
    printf '%s\n' "$1"
  } > "$STATUS_PATH" 2>/dev/null || true
}

open_app() {
  if [ "$NO_OPEN" -eq 1 ] || [ ! -f "$APP_PATH" ]; then
    return
  fi
  if [ -d "/Applications/Google Chrome.app" ] && open -a "/Applications/Google Chrome.app" "$APP_PATH" 2>/dev/null; then
    return
  fi
  if [ -d "$HOME/Applications/Google Chrome.app" ] && open -a "$HOME/Applications/Google Chrome.app" "$APP_PATH" 2>/dev/null; then
    return
  fi
  if [ -d "/Applications/Microsoft Edge.app" ] && open -a "/Applications/Microsoft Edge.app" "$APP_PATH" 2>/dev/null; then
    return
  fi
  open "$APP_PATH" 2>/dev/null || true
}

open_app

LOCAL_VERSION="$(cat "$VERSION_PATH" 2>/dev/null || true)"
MANIFEST_PATH="$TEMP_DIR/manifest.json"
MANIFEST_URL="https://raw.githubusercontent.com/$REPOSITORY/$BRANCH/manifest.json?t=$(date +%s)"

if ! curl -fsSL --connect-timeout 5 --max-time 20 --retry 2 \
  -H 'User-Agent: Seamless-Collage-macOS-Updater' \
  "$MANIFEST_URL" -o "$MANIFEST_PATH"; then
  write_status '更新检查失败；当前版本仍可正常使用。'
  exit 0
fi

REMOTE_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST_PATH" | head -n 1)"
if [ -z "$REMOTE_VERSION" ]; then
  write_status '更新清单无效；当前版本仍可正常使用。'
  exit 0
fi
if [ "$REMOTE_VERSION" = "$LOCAL_VERSION" ]; then
  write_status "已是最新版本：v$REMOTE_VERSION"
  exit 0
fi

ARCHIVE_PATH="$TEMP_DIR/repository.zip"
EXTRACT_DIR="$TEMP_DIR/repository"
SNAPSHOT_URL="https://codeload.github.com/$REPOSITORY/zip/refs/heads/$BRANCH?t=$(date +%s)"
if ! curl -fL --connect-timeout 8 --max-time 90 --retry 2 \
  -H 'User-Agent: Seamless-Collage-macOS-Updater' \
  "$SNAPSHOT_URL" -o "$ARCHIVE_PATH"; then
  write_status '更新下载失败；当前版本仍可正常使用。'
  exit 0
fi

mkdir -p "$EXTRACT_DIR"
if ! ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"; then
  write_status '更新包无法解压；当前版本仍可正常使用。'
  exit 0
fi
SNAPSHOT_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$SNAPSHOT_DIR" ] || [ ! -f "$SNAPSHOT_DIR/app.html" ]; then
  write_status '更新包缺少程序文件；当前版本仍可正常使用。'
  exit 0
fi

verify_manifest_hash() {
  local file_name="$1"
  local expected
  local actual
  expected="$(sed -n "s/.*\"path\"[[:space:]]*:[[:space:]]*\"$file_name\"[^}]*\"sha256\"[[:space:]]*:[[:space:]]*\"\([A-Fa-f0-9]*\)\".*/\1/p" "$MANIFEST_PATH" | head -n 1)"
  if [ -z "$expected" ]; then
    return 0
  fi
  actual="$(shasum -a 256 "$SNAPSHOT_DIR/$file_name" | awk '{print toupper($1)}')"
  expected="$(printf '%s' "$expected" | tr '[:lower:]' '[:upper:]')"
  [ "$actual" = "$expected" ]
}

if ! verify_manifest_hash "app.html" || ! verify_manifest_hash "使用说明.txt"; then
  write_status '更新包文件校验失败；当前版本仍可正常使用。'
  exit 0
fi

CHANGED=0
copy_if_changed() {
  local source_path="$1"
  local target_path="$2"
  local file_mode="$3"
  if [ ! -f "$source_path" ]; then
    return 0
  fi
  if [ -f "$target_path" ] && cmp -s "$source_path" "$target_path"; then
    return 0
  fi
  if ! cp "$source_path" "$target_path.tmp.$$" || ! chmod "$file_mode" "$target_path.tmp.$$"; then
    rm -f "$target_path.tmp.$$"
    return 1
  fi
  if ! mv -f "$target_path.tmp.$$" "$target_path"; then
    rm -f "$target_path.tmp.$$"
    return 1
  fi
  CHANGED=1
}

if ! copy_if_changed "$SNAPSHOT_DIR/app.html" "$APP_PATH" 644 \
  || ! copy_if_changed "$SNAPSHOT_DIR/使用说明.txt" "$RESOURCE_DIR/使用说明.txt" 644 \
  || ! copy_if_changed "$SNAPSHOT_DIR/launch-macos.sh" "$RESOURCE_DIR/launch-macos.sh" 755; then
  write_status '部分文件更新失败；请重新运行安装命令修复。'
  exit 0
fi

if ! printf '%s\n' "$REMOTE_VERSION" > "$VERSION_PATH.tmp.$$" || ! mv -f "$VERSION_PATH.tmp.$$" "$VERSION_PATH"; then
  rm -f "$VERSION_PATH.tmp.$$"
  write_status '版本记录更新失败；请重新运行安装命令修复。'
  exit 0
fi

if [ "$CHANGED" -eq 1 ]; then
  write_status "已更新至 v$REMOTE_VERSION；关闭浏览器页面后重新打开即可使用新版本。"
else
  write_status "已是最新版本：v$REMOTE_VERSION"
fi
