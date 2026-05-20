# VPaste

Mac 本地截图上传工具 - 按 `Cmd+Alt+V` 直接粘贴 CDN URL。

## 功能

- 📸 截图后按快捷键，自动上传到腾讯云 COS
- 🔗 URL 直接粘贴到光标位置（支持 SSH 终端、浏览器等任意输入框）
- 🚀 本地守护进程监听快捷键，无需手动启动
- ⚡️ 零依赖，纯 Go + Swift 实现

## 安装

```bash
# 克隆仓库
git clone https://github.com/your-username/vpaste.git
cd vpaste

# 一键安装
./install.sh
```

安装完成后，配置你的 COS 凭证：

```bash
# 编辑配置文件
nano ~/.config/vpaste/config.yaml
```

填入你的腾讯云 COS 配置：

```yaml
secret_id: "your_cos_secret_id"
secret_key: "your_cos_secret_key"
bucket: "your-bucket-name"
region: "ap-shanghai"
cdn_domain: "cdn.your-domain.com"  # 可选，没有 CDN 则留空
upload_path: "vpaste/temp"
```

## 使用

1. 截图（`Cmd+Shift+4` 或任意截图工具）
2. 把光标放在任意输入框
3. 按 `Cmd+Alt+V`
4. CDN URL 自动粘贴到光标位置

## 配置说明

| 字段 | 说明 |
|------|------|
| `secret_id` | 腾讯云 API SecretId |
| `secret_key` | 腾讯云 API SecretKey |
| `bucket` | COS 存储桶名称（含 APPID） |
| `region` | 存储桶所在地域，如 `ap-shanghai` |
| `cdn_domain` | CDN 加速域名（可选） |
| `upload_path` | COS 存储路径前缀 |

## 权限说明

首次使用需要授予辅助功能权限：

1. 打开「系统设置」→「隐私与安全性」→「辅助功能」
2. 添加 `vpaste-daemon.app`
3. 勾选启用

## 目录结构

```
vpaste/
├── main.go           # CLI 入口
├── config/           # 配置读取
├── clipboard/        # 剪贴板操作
├── cos/              # COS 上传
├── daemon/           # 快捷键监听守护进程
├── config.example.yaml
└── install.sh        # 一键安装脚本
```

## 日志

查看运行日志：

```bash
log show --predicate 'process == "vpaste-daemon"' --last 5m
```

## 停止守护进程

```bash
pkill -f vpaste-daemon
```

## 重新启动

```bash
launchctl load ~/Library/LaunchAgents/com.vpaste.daemon.plist
```

## License

MIT
