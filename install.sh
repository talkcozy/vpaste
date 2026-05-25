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

# 7. 安装 Launch Agent
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
    <string>/tmp/vpaste_daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vpaste_daemon.log</string>
</dict>
</plist>
EOF

# 8. 重启守护进程
echo "重启守护进程..."
launchctl bootout gui/$(id -u)/com.vpaste.daemon 2>/dev/null || true
sleep 1
launchctl bootstrap gui/$(id -u) "$LAUNCH_AGENT"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "安装位置:"
echo "  CLI:     $INSTALL_DIR/vpaste"
echo "  Daemon:  $INSTALL_DIR/vpaste-daemon"
echo "配置:     $CONFIG_DIR/config.yaml"
echo "快捷键:   Cmd+Alt+V"
echo ""
echo "状态栏菜单:"
echo "  - 点击 [V] 图标上传剪贴板图片"
echo "  - 查看历史上传记录"
echo ""
echo "⚠️  首次使用需要授予辅助功能权限:"
echo "    系统设置 → 隐私与安全性 → 辅助功能 → 点 + 添加 $INSTALL_DIR/vpaste-daemon"
echo ""
echo "使用方法:"
echo "    1. 截图或复制图片到剪贴板"
echo "    2. 按 Cmd+Alt+V 或点击状态栏图标"
echo "    3. CDN URL 自动粘贴到光标位置"
echo ""
echo "查看日志: tail -f /tmp/vpaste_daemon.log"
