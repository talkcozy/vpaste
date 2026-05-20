# VPaste：让 SSH 终端也能"粘贴"截图

> 一键截图上传，URL 直接输入到光标位置 —— 解决远程开发场景下的图片粘贴难题

## 痛点：SSH 终端无法粘贴图片

作为一个开发者，你是否遇到过这样的场景：

1. 在本地 Mac 截图了一张 UI 问题
2. SSH 连接到远程服务器，想用 Claude Code 或 Codex 分析这个问题
3. 按 `Cmd+V` 想粘贴图片……但终端只能粘贴文本，图片丢失了
4. 只能手动把图片上传到某处，复制 URL，再粘贴 URL

这个流程太繁琐了！尤其是在和 AI 助手交互时，图片输入的效率直接影响开发体验。

![VPaste 使用前后对比](https://webstatic.aiproxy.vip/output/20260520/51175/fd7cef16-3928-4fd3-b4d1-435302243829/0d478642-9fa9-45a3-8cff-282041402e29.png)

## 解决方案：VPaste

VPaste 是一个 Mac 本地工具，核心思路很简单：

**截图在剪贴板 → 按 `Cmd+Alt+V` → CDN URL 直接"打"到光标位置**

原来的 `Cmd+V` 粘贴图片功能完全保留，两个快捷键各司其职：

| 快捷键 | 功能 |
|--------|------|
| `Cmd+V` | 正常粘贴剪贴板内容（图片/文本） |
| `Cmd+Alt+V` | 上传图片，粘贴 CDN URL |

## 技术实现

![VPaste 技术架构](https://webstatic.aiproxy.vip/output/20260520/51175/0a63d3ae-52c8-4f2f-9fd9-666dfcbcb600/f2511296-271b-4dcf-928d-fabff3de69cd.png)

### 1. 快捷键监听

用 Swift 编写一个后台守护进程，通过 `CGEventTap` 监听全局键盘事件：

```swift
func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, 
                      event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // V = keyCode 9, Cmd + Alt
        if keyCode == 9 && flags.contains(.maskCommand) && flags.contains(.maskAlternate) {
            runVPaste()  // 异步执行上传
            return nil   // 消费事件，不传递
        }
    }
    return Unmanaged.passRetained(event)
}
```

### 2. 剪贴板图片读取

macOS 剪贴板中的图片默认是 **TIFF 格式**，需要转换成 PNG：

```go
// AppleScript 读取剪贴板图片
script := `
    set theImage to the clipboard as TIFF picture
    write theImage to file "/tmp/vpaste/image.png"
`

// sips 转换为真正的 PNG
exec.Command("sips", "-s", "format", "png", tempPath, "--out", tempPath).Run()
```

### 3. 上传到 COS

使用腾讯云 COS SDK 上传，生成带日期路径的文件名：

```go
func (c *COSClient) UploadFile(ctx context.Context, filePath string) (string, error) {
    key := fmt.Sprintf("vpaste/temp/%s/%s.png", 
        time.Now().Format("2006/01/02"), filename)
    
    client.Object.Put(ctx, key, reader, opt)
    
    return fmt.Sprintf("https://%s/%s", c.cdnDomain, key), nil
}
```

### 4. URL 输入到光标位置

不是用键盘模拟逐字输入（会被输入法干扰），而是：

1. 把 URL 写入剪贴板
2. 模拟 `Cmd+V` 粘贴

```swift
func pasteURL(_ url: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(url, forType: .string)
    
    // 模拟 Cmd+V
    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
    let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    vDown?.flags = .maskCommand
    // ... post events
}
```

## 安装使用

```bash
# 克隆仓库
git clone https://github.com/talkcozy/vpaste.git
cd vpaste

# 一键安装
./install.sh
```

配置你的 COS 凭证：

```yaml
# ~/.config/vpaste/config.yaml
secret_id: "your_cos_secret_id"
secret_key: "your_cos_secret_key"
bucket: "your-bucket-1234567890"
region: "ap-shanghai"
cdn_domain: "cdn.your-domain.com"
upload_path: "vpaste/temp"
```

首次使用需要授予辅助功能权限（用于监听全局快捷键）。

## 设计哲学

1. **最小改动**：不改变原有的 `Cmd+V` 行为，新增独立快捷键
2. **零感知**：后台守护进程自动启动，无需手动操作
3. **即刻可用**：URL 直接出现在光标位置，不需要额外复制
4. **云端销毁**：可配置 COS 生命周期规则，自动清理临时图片

## 适配场景

- ✅ SSH 终端远程开发
- ✅ Claude Code / Codex AI 助手交互
- ✅ 浏览器地址栏、搜索框
- ✅ 任何支持文本输入的地方

## 开源

项目已在 GitHub 开源：**https://github.com/talkcozy/vpaste**

MIT License，欢迎 Star、Fork、PR！