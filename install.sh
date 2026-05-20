#!/bin/bash
# VPaste 一键安装脚本 (用户目录版本，无需 sudo)
# 使用方法: ./install.sh

set -e

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== VPaste 安装脚本 ==="

# 1. 创建安装目录
mkdir -p "$INSTALL_DIR"

# 2. 编译 vpaste CLI
echo "编译 vpaste..."
cd "$SCRIPT_DIR"
go build -o vpaste .

# 3. 编译 vpaste-daemon (快捷键监听器)
echo "编译快捷键监听器..."
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

# 6. 创建配置目录
CONFIG_DIR="$HOME/.config/vpaste"
mkdir -p "$CONFIG_DIR"

# 7. 如果配置文件不存在，复制
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    if [ -f "$SCRIPT_DIR/config.yaml" ]; then
        cp "$SCRIPT_DIR/config.yaml" "$CONFIG_DIR/config.yaml"
    else
        cp "$SCRIPT_DIR/config.example.yaml" "$CONFIG_DIR/config.yaml"
        echo "已创建示例配置文件，请编辑 $CONFIG_DIR/config.yaml"
    fi
fi

# 8. 安装 Launch Agent (自动启动守护进程)
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
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/vpaste-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vpaste-daemon.log</string>
</dict>
</plist>
EOF

# 9. 启动守护进程
echo "启动快捷键监听服务..."
launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "安装位置:"
echo "  CLI:     $INSTALL_DIR/vpaste"
echo "  Daemon:  $INSTALL_DIR/vpaste-daemon"
echo "配置:     $CONFIG_DIR/config.yaml"
echo "快捷键:   Cmd+Alt+V (立即生效)"
echo ""
echo "⚠️  首次使用需要授予辅助功能权限:"
echo "    系统设置 → 隐私与安全性 → 辅助功能 → 添加 vpaste-daemon"
echo ""
echo "使用方法:"
echo "    1. 截图或复制图片到剪贴板"
echo "    2. 按 Cmd+Alt+V"
echo "    3. CDN URL 自动粘贴到光标位置"
echo ""
echo "查看日志: tail -f /tmp/vpaste-daemon.log"