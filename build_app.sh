#!/bin/bash
# 构建 EyeTimer.app —— SwiftPM 编译 + 手工组装 bundle + ad-hoc 签名
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="EyeTimer"
BUNDLE_ID="com.eyetimer.app"
BUILD_DIR="$ROOT/.build"
APP_VERSION="${APP_VERSION:-$(cat "$ROOT/VERSION")}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
APP_ARCH="${APP_ARCH:-$(uname -m)}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$APP_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "版本格式错误：APP_VERSION 应为 X.Y.Z，APP_BUILD_NUMBER 应为整数" >&2
    exit 1
fi
if [[ "$APP_ARCH" != "arm64" && "$APP_ARCH" != "x86_64" ]]; then
    echo "不支持的架构: $APP_ARCH" >&2
    exit 1
fi
APP_DIR="$ROOT/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "==> [1/5] 编译 (release)"
cd "$ROOT"
build_args=(-c release --disable-sandbox --product "$APP_NAME" --arch "$APP_ARCH")
swift build "${build_args[@]}"

BINARY="$(swift build "${build_args[@]}" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
    echo "构建产物不存在: $BINARY" >&2
    exit 1
fi
echo "    二进制: $BINARY"

echo "==> [2/5] 组装 App Bundle"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/LICENSE" "$RES_DIR/LICENSE.txt"

echo "==> [3/5] 生成图标"
ICON_TMP="$ROOT/.build/icons"
rm -rf "$ICON_TMP"
mkdir -p "$ICON_TMP"
swift "$ROOT/Tools/make_icon.swift" "$ICON_TMP" 2>/dev/null | tail -2 || echo "    (图标生成跳过)"
if [[ -f "$ICON_TMP/AppIcon.icns" ]]; then
    cp "$ICON_TMP/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$ICON_TMP/AppIcon.iconset"
elif [[ -f "$ICON_TMP/AppIcon.png" ]]; then
    cp "$ICON_TMP/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
    # 用 png 兜底时改 plist 指向
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.png" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
fi

# 写入版本号到 plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

echo "==> [4/5] 生成 PkgInfo + 签名"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
# ad-hoc 签名（本地运行足够；若要分发给其他机器需开发者证书）
codesign --force --deep --sign - "$APP_DIR" 2>&1 | sed 's/^/    /'

echo "==> [5/5] 校验"
codesign --verify --strict --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/    /'
echo ""
echo "构建完成: $APP_DIR"
echo "安装: cp -R \"$APP_DIR\" /Applications/"
echo "运行: open \"$APP_DIR\""
