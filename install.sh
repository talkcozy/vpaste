#!/bin/bash
# VPaste 一键安装脚本 (用户目录版本，无需 sudo)
# 使用方法: ./install.sh

set -e

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="VPaste"
APP_BUNDLE="/Applications/${APP_NAME}.app"

echo "=== VPaste 安装脚本 ==="

# 1. 创建安装目录
mkdir -p "$INSTALL_DIR"

# 2. 编译 vpaste CLI
echo "编译 vpaste..."
cd "$SCRIPT_DIR"
go build -o vpaste .

# 3. 编译 vpaste-daemon (Swift)
echo "编译菜单栏守护进程..."
swiftc -o vpaste-daemon daemon/main.swift

# 4. 安装到用户目录
echo "安装到 $INSTALL_DIR..."
cp vpaste "$INSTALL_DIR/vpaste"
cp vpaste-daemon "$INSTALL_DIR/vpaste-daemon"
chmod +x "$INSTALL_DIR/vpaste" "$INSTALL_DIR/vpaste-daemon"

# 5. 确保 PATH 包含安装目录
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo "添加 $INSTALL_DIR 到 PATH..."
    if [ -f "$HOME/.zshrc" ]; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.bashrc"
    fi
    export PATH="$INSTALL_DIR:$PATH"
fi

# 6. 配置目录
CONFIG_DIR="$HOME/.config/vpaste"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    if [ -f "$SCRIPT_DIR/config.yaml" ]; then
        cp "$SCRIPT_DIR/config.yaml" "$CONFIG_DIR/config.yaml"
    else
        cp "$SCRIPT_DIR/config.example.yaml" "$CONFIG_DIR/config.yaml"
        echo "已创建示例配置文件，请编辑 $CONFIG_DIR/config.yaml"
    fi
fi

# 7. 创建 .app Bundle
echo "创建应用 Bundle..."
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制二进制文件
cp "$INSTALL_DIR/vpaste" "$APP_BUNDLE/Contents/MacOS/vpaste"
cp "$INSTALL_DIR/vpaste-daemon" "$APP_BUNDLE/Contents/MacOS/vpaste-daemon"
chmod +x "$APP_BUNDLE/Contents/MacOS/vpaste" "$APP_BUNDLE/Contents/MacOS/vpaste-daemon"

# 写入 Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>VPaste</string>
    <key>CFBundleDisplayName</key>
    <string>VPaste</string>
    <key>CFBundleIdentifier</key>
    <string>com.vpaste.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>vpaste-daemon</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 创建 AppIcon.icns
ICON_SRC="$SCRIPT_DIR/launcher/AppIcon_1024.png"
if [ -f "$ICON_SRC" ]; then
    echo "生成应用图标..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"

    # 用 sips 将 1024x1024 PNG 缩放为所有标准尺寸
    for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" \
                "32:icon_32x32.png" "64:icon_32x32@2x.png" \
                "128:icon_128x128.png" "256:icon_128x128@2x.png" \
                "256:icon_256x256.png" "512:icon_256x256@2x.png" \
                "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
        SIZE="${spec%%:*}"
        FILENAME="${spec##*:}"
        sips -z "$SIZE" "$SIZE" "$ICON_SRC" --out "$ICONSET_DIR/$FILENAME" >/dev/null 2>&1
    done

    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET_DIR")"
    echo "应用图标已生成"
else
    echo "⚠️  未找到图标文件: $ICON_SRC，跳过图标生成"
fi

# 创建卸载脚本
cat > "$APP_BUNDLE/Contents/Resources/uninstall.sh" << 'UNINSTALL'
#!/bin/bash
echo "正在卸载 VPaste..."
launchctl bootout gui/$(id -u)/com.vpaste.daemon 2>/dev/null || true
rm -f "$HOME/.local/bin/vpaste"
rm -f "$HOME/.local/bin/vpaste-daemon"
rm -rf "/Applications/VPaste.app"
echo "已卸载。配置文件保留在 ~/.config/vpaste/"
UNINSTALL
chmod +x "$APP_BUNDLE/Contents/Resources/uninstall.sh"

echo "应用已安装到 $APP_BUNDLE"

# 8. 安装 Launch Agent
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.vpaste.daemon.plist"

cat > "$LAUNCH_AGENT" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vpaste.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/vpaste-daemon</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/vpaste_daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vpaste_daemon.log</string>
</dict>
</plist>
EOF

# 9. 重启守护进程
echo "重启守护进程..."
launchctl bootout gui/$(id -u)/com.vpaste.daemon 2>/dev/null || true
sleep 1
launchctl bootstrap gui/$(id -u) "$LAUNCH_AGENT"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "安装位置:"
echo "  应用:   $APP_BUNDLE"
echo "  CLI:    $INSTALL_DIR/vpaste"
echo "  Daemon: $INSTALL_DIR/vpaste-daemon"
echo "配置:     $CONFIG_DIR/config.yaml"
echo "快捷键:   Cmd+Alt+V"
echo ""
echo "状态栏菜单:"
echo "  - 点击 [V] 图标上传剪贴板图片"
echo "  - 查看历史上传记录"
echo "  - 图形化设置界面"
echo ""
echo "⚠️  首次使用需要授予辅助功能权限:"
echo "    系统设置 → 隐私与安全性 → 辅助功能 → 点 + 添加 $INSTALL_DIR/vpaste-daemon"
echo ""
echo "使用方法:"
echo "    1. 从 /Applications 双击 VPaste 启动"
echo "    2. 截图或复制图片到剪贴板"
echo "    3. 按 Cmd+Alt+V 或点击状态栏图标"
echo "    4. CDN URL 自动粘贴到光标位置"
echo ""
echo "查看日志: tail -f /tmp/vpaste_daemon.log"
