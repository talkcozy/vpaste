# VPaste

<p align="center">
  <b>Mac Clipboard Image Uploader</b><br>
  截图 → 上传 → 自动粘贴 CDN URL
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#changelog">Changelog</a>
</p>

---

## Features | 功能特性

| Feature | Description |
|---------|-------------|
| 📸 **Screenshot Upload** | Auto-upload clipboard images to Tencent COS |
| 🔗 **Auto Paste URL** | CDN URL pasted directly at cursor position |
| 📊 **Menu Bar Icon** | Click **V** icon to upload, view history, or quit |
| 📁 **Upload History** | Standalone window showing last 100 uploads with copy-to-clipboard |
| ⌨️ **Global Hotkey** | `Cmd+Alt+V` works in any app |
| 🧹 **Auto Cleanup** | Old files cleaned automatically (configurable retention) |
| 🚀 **Daemon Mode** | Background process with menu bar presence 24/7 |
| ⚡️ **Zero Dependencies** | Pure Go + Swift implementation |

---

## Installation | 安装

```bash
git clone https://github.com/talkcozy/vpaste.git
cd vpaste
./install.sh
```

### Configuration | 配置

Create and edit config file:
```bash
mkdir -p ~/.config/vpaste
cp config.example.yaml ~/.config/vpaste/config.yaml
nano ~/.config/vpaste/config.yaml
```

**Config Example | 配置示例：**

```yaml
secret_id: "your_cos_secret_id"
secret_key: "your_cos_secret_key"
bucket: "your-bucket-name-1234567890"
region: "ap-shanghai"
cdn_domain: "cdn.your-domain.com"  # Optional | 可选
upload_path: "vpaste/temp"
temp_retention_hours: 24  # Auto-delete after 24h | 24小时后自动删除
```

---

## Usage | 使用方法

### Method 1: Hotkey | 快捷键

1. Screenshot or copy an image to clipboard  
   截图或复制图片到剪贴板
2. Press `Cmd+Alt+V`  
   按 `Cmd+Alt+V`
3. CDN URL auto-pasted at cursor position  
   CDN URL 自动粘贴到光标位置

### Method 2: Menu Bar | 状态栏菜单

1. Click the **V** icon in the menu bar  
   点击状态栏的 **V** 图标
2. Select "上传剪贴板图片" to upload  
   选择"上传剪贴板图片"
3. Select "历史记录" to view past uploads  
   选择"历史记录"查看上传历史

### Command Line | 命令行

```bash
vpaste           # Upload clipboard image | 上传剪贴板图片
vpaste stats     # View upload statistics | 查看上传统计
vpaste clean     # Manual cleanup | 手动清理过期文件
```

---

## Permissions | 权限设置

**First-time setup requires Accessibility permission:**  
**首次使用需要授予辅助功能权限：**

1. Open **System Settings** → **Privacy & Security** → **Accessibility**  
   打开「系统设置」→「隐私与安全性」→「辅助功能」

2. Click **+** and navigate to `~/.local/bin/vpaste-daemon`  
   点 **+** 添加 `~/.local/bin/vpaste-daemon`
   (Press `Cmd+Shift+G` to paste the path | 按 `Cmd+Shift+G` 粘贴路径)

3. Enable the checkbox  
   勾选启用

> **Note:** After each recompile (`./install.sh`), you may need to re-add the binary  
> **注意：** 每次重新编译后可能需要重新添加二进制文件

---

## Project Structure | 项目结构

```
vpaste/
├── main.go              # CLI entry point | 命令行入口
├── config/              # Config loading | 配置读取
│   └── config.go
├── clipboard/           # Clipboard operations | 剪贴板操作
│   └── clipboard.go
├── cos/                 # COS upload/cleanup | COS 上传/清理
│   └── cos.go
├── db/                  # Local record database | 本地记录数据库
│   └── db.go
├── daemon/              # Menu bar daemon | 状态栏守护进程
│   └── main.swift
├── config.example.yaml  # Example config | 配置示例
├── install.sh           # Install script | 安装脚本
└── README.md
```

---

## Logs | 日志查看

```bash
tail -f /tmp/vpaste_daemon.log
```

---

## Troubleshooting | 故障排除

| Issue | Solution |
|-------|----------|
| "NO_IMAGE" output | Clipboard has no image. Take a screenshot first. |
| Upload fails | Check COS credentials and network connection |
| Hotkey not working | Grant Accessibility permission to `~/.local/bin/vpaste-daemon` |
| No menu bar icon | Grant Accessibility permission, then restart: `! launchctl bootout gui/$(id -u)/com.vpaste.daemon && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.vpaste.daemon.plist` |
| Two V icons | Kill stale test processes: `pkill -f vpaste_minimal` |
| Cleanup not running | Check `temp_retention_hours` config, default is 24h |

---

## Changelog | 更新日志

### v3.0 (2025-05-25)
- ✨ **New**: Menu bar status icon with upload and history menu
- ✨ **New**: Standalone history window with copy-to-clipboard
- 🔧 **Fix**: macOS 26 (Tahoe) compatibility - Carbon hotkey, standalone binary
- 🔧 **Fix**: Accessibility permission now requires per-binary grant

### v2.0 (2025-05-21)
- ✨ **New**: Automatic cleanup with local database tracking
- ✨ **New**: `vpaste clean` and `vpaste stats` commands
- ✨ **New**: `temp_retention_hours` config option

### v1.0 (Initial Release)
- 🎉 Clipboard image upload to Tencent COS
- 🎉 Global hotkey `Cmd+Alt+V`
- 🎉 Auto-paste CDN URL at cursor position
- 🎉 Background daemon for hotkey listening

---

## License | 许可证

MIT License - feel free to use and modify!  
MIT 许可证 - 自由使用和修改！
