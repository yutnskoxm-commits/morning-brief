#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="FinFlash"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "⚡ Building FinFlash desktop app..."
echo ""

# 1. 清理旧的构建
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# 2. 用 swiftc 编译 Swift 源码
echo "  → Compiling Swift source..."
swiftc "$SCRIPT_DIR/FinFlash.swift" \
    -o "$MACOS_DIR/$APP_NAME" \
    -framework Cocoa \
    -framework WebKit \
    -O

echo "  ✓ Binary compiled: $MACOS_DIR/$APP_NAME"

# 3. 生成 Info.plist
echo "  → Creating Info.plist..."
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>FinFlash</string>
    <key>CFBundleIdentifier</key>
    <string>com.finflash.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FinFlash</string>
    <key>CFBundleDisplayName</key>
    <string>FinFlash</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 FinFlash.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# 4. 生成 PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# 5. 生成 App 图标
echo "  → Generating app icon..."
ICON_DIR="$RESOURCES_DIR/AppIcon.iconset"
mkdir -p "$ICON_DIR"

python3 "$SCRIPT_DIR/gen_icon.py" "$ICON_DIR"

if command -v iconutil &> /dev/null; then
    if iconutil -c icns "$ICON_DIR" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null; then
        echo "  ✓ Generated AppIcon.icns"
        rm -rf "$ICON_DIR"
    else
        echo "  ⚠ iconutil failed, skipping icon"
    fi
fi

# 6. 输出结果
echo ""
echo "✅ Build complete!"
echo "   App: $APP_BUNDLE"
echo ""
echo "💡 使用方式："
echo "   open '$BUILD_DIR'                          # 在 Finder 中打开"
echo "   cp -r '$APP_BUNDLE' /Applications/         # 安装到 Applications"
echo "   open '$APP_BUNDLE'                         # 直接启动"
