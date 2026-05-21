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

## 🆕 What's New | 最新功能

### v2.0 - Automatic Cleanup | 自动清理功能

> **No more manual cleanup for temporary images!**  
> **临时图片再也不用手动清理了！**

- ✅ **Automatic async cleanup** - Old files are cleaned up automatically on every paste (max once per hour)  
  **异步自动清理** - 每次粘贴时自动清理过期文件（每小时最多一次）

- ✅ **Local record tracking** - All uploads saved to `~/.config/vpaste/records.json`  
  **本地记录追踪** - 所有上传记录保存到本地 JSON 文件

- ✅ **Smart retention** - Files older than `temp_retention_hours` (default 24h) auto-deleted  
  **智能保留策略** - 超过 `temp_retention_hours`（默认24小时）的文件自动删除

- ✅ **Zero cron setup** - Pure application-level implementation, no system cron needed  
  **无需系统定时任务** - 纯应用层实现，无需配置系统 cron

**New Commands | 新增命令：**
```bash
vpaste clean    # Manual cleanup | 手动清理过期文件
vpaste stats    # View upload statistics | 查看上传统计
```

---

## Features | 功能特性

| Feature | Description |
|---------|-------------|
| 📸 **Screenshot Upload** | Auto-upload clipboard images to Tencent COS |
| 🔗 **Auto Paste URL** | CDN URL pasted directly at cursor position |
| 🧹 **Auto Cleanup** | Old files cleaned automatically (configurable retention) |
| 📊 **Upload History** | Local JSON database tracks all uploads |
| ⌨️ **Global Hotkey** | `Cmd+Alt+V` works in any app (terminal, browser, IDE) |
| 🚀 **Daemon Mode** | Background process listens for hotkeys 24/7 |
| ⚡️ **Zero Dependencies** | Pure Go + Swift implementation |

---

## Installation | 安装

```bash
# Clone the repository
# 克隆仓库
git clone https://github.com/talkcozy/vpaste.git
cd vpaste

# One-click install
# 一键安装
./install.sh
```

### Configuration | 配置

Create and edit config file:  
创建并编辑配置文件：

```bash
mkdir -p ~/.config/vpaste
cp config.example.yaml ~/.config/vpaste/config.yaml
nano ~/.config/vpaste/config.yaml
```

**Config Example | 配置示例：**

```yaml
# Tencent Cloud COS credentials
# 腾讯云 COS 凭证
secret_id: "your_cos_secret_id"
secret_key: "your_cos_secret_key"
# token: ""  # Optional: for temporary credentials

# Bucket settings
# 存储桶设置
bucket: "your-bucket-name-1234567890"
region: "ap-shanghai"
cdn_domain: "cdn.your-domain.com"  # Optional | 可选
upload_path: "vpaste/temp"

# Cleanup settings (NEW!)
# 清理设置（新增！）
temp_retention_hours: 24  # Delete files older than 24h | 24小时后自动删除
```

---

## Usage | 使用方法

### Basic | 基础用法

1. **Take a screenshot** (`Cmd+Shift+4` or any screenshot tool)  
   **截图**（`Cmd+Shift+4` 或任意截图工具）

2. **Place cursor** in any input field  
   **放置光标**到任意输入框

3. **Press hotkey** `Cmd+Alt+V`  
   **按快捷键** `Cmd+Alt+V`

4. **CDN URL auto-pasted** at cursor position  
   **CDN URL 自动粘贴**到光标位置

### Command Line | 命令行

```bash
# Upload clipboard image
# 上传剪贴板图片（默认命令）
vpaste

# View upload statistics
# 查看上传统计
vpaste stats
# Output example:
# Total uploads: 42
# Oldest record: 2025-05-20 10:30:00
# Last clean: 2025-05-21 09:15:00

# Manual cleanup (delete files older than retention period)
# 手动清理（删除超过保留时间的文件）
vpaste clean

# Output example:
# Cleaning up files older than 24 hours...
# Deleted 15 old file(s)
```

---

## Configuration Reference | 配置说明

| Field | Description | Default |
|-------|-------------|---------|
| `secret_id` | Tencent Cloud API SecretId | - |
| `secret_key` | Tencent Cloud API SecretKey | - |
| `token` | Temporary credentials token (optional) | - |
| `bucket` | COS bucket name (with APPID) | - |
| `region` | Bucket region, e.g. `ap-shanghai` | - |
| `cdn_domain` | CDN domain (optional) | - |
| `upload_path` | COS path prefix | `vpaste/temp` |
| `temp_retention_hours` | **File retention time (hours)** ⭐ | `24` |

---

## How Auto-Cleanup Works | 自动清理原理

```
Paste Image
    ↓
Upload to COS → Save record to ~/.config/vpaste/records.json
    ↓
Check: Last clean > 1 hour ago?
    ↓
    Yes → Async cleanup (non-blocking)
          Delete COS files older than temp_retention_hours
          Remove cleaned records from local DB
    ↓
Return CDN URL (upload not blocked by cleanup)
```

**Key Points | 关键点：**
- Cleanup runs **asynchronously** - doesn't block your paste operation  
  清理是**异步执行**的 - 不会阻塞粘贴操作
- Max **once per hour** - prevents frequent API calls  
  每小时最多执行**一次** - 避免频繁调用 API
- Local DB **auto-limits** to 1000 records (oldest auto-removed)  
  本地数据库**自动限制**1000条记录（最旧的自动移除）

---

## Permissions | 权限设置

**First-time setup requires Accessibility permission:**  
**首次使用需要辅助功能权限：**

1. Open **System Settings** → **Privacy & Security** → **Accessibility**  
   打开「系统设置」→「隐私与安全性」→「辅助功能」

2. Add `vpaste-daemon.app`  
   添加 `vpaste-daemon.app`

3. Enable the checkbox  
   勾选启用

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
├── db/                  # Local record database (NEW!) | 本地记录数据库（新增）
│   └── db.go
├── daemon/              # Hotkey daemon | 快捷键守护进程
│   └── daemon.swift
├── config.example.yaml  # Example config | 配置示例
├── install.sh           # Install script | 安装脚本
└── README.md
```

---

## Logs | 日志查看

```bash
# View daemon logs
# 查看守护进程日志
log show --predicate 'process == "vpaste-daemon"' --last 5m
```

---

## Troubleshooting | 故障排除

| Issue | Solution |
|-------|----------|
| "NO_IMAGE" output | Clipboard has no image. Take a screenshot first. |
| Upload fails | Check COS credentials and network connection |
| Hotkey not working | Grant Accessibility permission in System Settings |
| Cleanup not running | Check `temp_retention_hours` config, default is 24h |

---

## Changelog | 更新日志

### v2.0 (2025-05-21)
- ✨ **New**: Automatic cleanup with local database tracking
- ✨ **New**: `vpaste clean` command for manual cleanup
- ✨ **New**: `vpaste stats` command for upload statistics
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
