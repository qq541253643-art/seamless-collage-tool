#!/bin/bash
set -euo pipefail

REPOSITORY="qq541253643-art/seamless-collage-tool"
BRANCH="main"
APP_NAME="无缝拼图工具.app"
APP_DIR="$HOME/Applications/$APP_NAME"
DESKTOP_LINK="$HOME/Desktop/$APP_NAME"
NO_OPEN=0

for argument in "$@"; do
  case "$argument" in
    --no-open) NO_OPEN=1 ;;
    *) printf '未知参数：%s\n' "$argument" >&2; exit 2 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  printf '请在 macOS 上运行此安装程序。\n' >&2
  exit 1
fi

case "$(uname -m)" in
  arm64) ;;
  x86_64) printf '检测到 Intel Mac；工具仍可运行，Apple Silicon 使用体验更好。\n' ;;
  *) printf '不支持的 Mac 架构：%s\n' "$(uname -m)" >&2; exit 1 ;;
esac

for command_name in curl ditto find sed shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf '缺少系统命令：%s\n' "$command_name" >&2
    exit 1
  fi
done

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/seamless-collage-install.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE_PATH="$TEMP_DIR/repository.zip"
EXTRACT_DIR="$TEMP_DIR/repository"
STAGE_APP="$TEMP_DIR/app"
CACHE_BUSTER="$(date +%s)"
SNAPSHOT_URL="https://codeload.github.com/$REPOSITORY/zip/refs/heads/$BRANCH?t=$CACHE_BUSTER"

printf '正在下载无缝拼图工具…\n'
curl -fL --connect-timeout 10 --max-time 90 --retry 3 \
  -H 'User-Agent: Seamless-Collage-macOS-Installer' \
  "$SNAPSHOT_URL" -o "$ARCHIVE_PATH"

mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"
SNAPSHOT_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$SNAPSHOT_DIR" ]; then
  printf '下载内容无法解压。\n' >&2
  exit 1
fi

MANIFEST_PATH="$SNAPSHOT_DIR/manifest.json"
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST_PATH" | head -n 1)"
if [ -z "$VERSION" ]; then
  printf '版本清单无效。\n' >&2
  exit 1
fi

for required_file in app.html launch-macos.sh 使用说明.txt; do
  if [ ! -f "$SNAPSHOT_DIR/$required_file" ]; then
    printf '安装包缺少文件：%s\n' "$required_file" >&2
    exit 1
  fi
done

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
  if [ "$actual" != "$expected" ]; then
    printf '文件校验失败：%s\n' "$file_name" >&2
    exit 1
  fi
}

verify_manifest_hash "app.html"
verify_manifest_hash "使用说明.txt"

mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
cp "$SNAPSHOT_DIR/app.html" "$STAGE_APP/Contents/Resources/app.html"
cp "$SNAPSHOT_DIR/使用说明.txt" "$STAGE_APP/Contents/Resources/使用说明.txt"
cp "$SNAPSHOT_DIR/launch-macos.sh" "$STAGE_APP/Contents/Resources/launch-macos.sh"
printf '%s\n' "$VERSION" > "$STAGE_APP/Contents/Resources/version.txt"

cat > "$STAGE_APP/Contents/MacOS/launcher" <<'LAUNCHER'
#!/bin/bash
set -u
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RESOURCE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../Resources" && pwd)"
if [ ! -f "$RESOURCE_DIR/launch-macos.sh" ]; then
  printf '启动文件缺失，请重新安装无缝拼图工具。\n' >&2
  exit 1
fi
exec /bin/bash "$RESOURCE_DIR/launch-macos.sh"
LAUNCHER

cat > "$STAGE_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>无缝拼图工具</string>
  <key>CFBundleDisplayName</key>
  <string>无缝拼图工具</string>
  <key>CFBundleIdentifier</key>
  <string>art.qq541253643.seamless-collage-tool</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>launcher</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod 755 "$STAGE_APP/Contents/MacOS/launcher"
chmod 755 "$STAGE_APP/Contents/Resources/launch-macos.sh"
chmod 644 "$STAGE_APP/Contents/Info.plist" "$STAGE_APP/Contents/Resources/app.html" "$STAGE_APP/Contents/Resources/使用说明.txt" "$STAGE_APP/Contents/Resources/version.txt"

mkdir -p "$HOME/Applications"
OLD_APP="${APP_DIR}.old.$$"
if [ -e "$APP_DIR" ]; then
  mv "$APP_DIR" "$OLD_APP"
fi
if ! mv "$STAGE_APP" "$APP_DIR"; then
  if [ -e "$OLD_APP" ]; then
    mv "$OLD_APP" "$APP_DIR"
  fi
  printf '安装失败，已保留原版本。\n' >&2
  exit 1
fi
if [ -e "$OLD_APP" ]; then
  rm -rf "$OLD_APP"
fi

if [ -d "$HOME/Desktop" ]; then
  ln -sfn "$APP_DIR" "$DESKTOP_LINK"
fi
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

printf '已安装：%s\n' "$APP_DIR"
printf '桌面快捷方式：%s\n' "$DESKTOP_LINK"
printf '版本：v%s\n' "$VERSION"

if [ "$NO_OPEN" -eq 0 ]; then
  open "$APP_DIR" 2>/dev/null || open "$APP_DIR/Contents/Resources/app.html" 2>/dev/null || true
fi
