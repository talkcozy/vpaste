import Cocoa
import Carbon

// MARK: - Logging

func vlog(_ msg: String) {
    "\(msg)\n".withCString { ptr in
        let f = fopen("/tmp/vpaste_daemon.log", "a")
        if let f = f { fputs(ptr, f); fclose(f) }
    }
}

// MARK: - Upload Record Model

struct UploadRecord: Codable {
    let key: String
    let cdn_url: String
    let uploaded_at: Date
    let size: Int64
}

struct RecordsDB: Codable {
    let records: [UploadRecord]
    let last_clean: Date
}

// MARK: - VPaste Execution

func runClean(hours: Int) {
    vlog("Cleaning image bed (older than \(hours)h)...")

    let vpastePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/vpaste").path

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", "\(vpastePath) clean \(hours)"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        vlog("Clean result: \(output)")
    } catch {
        vlog("Clean error: \(error)")
    }
}

func runVPaste() {
    vlog("Running upload...")

    let vpastePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/vpaste").path

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", vpastePath]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        vlog("Result: \(output)")

        if output == "NO_IMAGE" || output.isEmpty {
            vlog("No image in clipboard")
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)

            DispatchQueue.main.async {
                let src = CGEventSource(stateID: .combinedSessionState)
                CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)?.post(tap: .cgSessionEventTap)
                let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
                vDown?.flags = .maskCommand
                vDown?.post(tap: .cgSessionEventTap)
                let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                vUp?.flags = .maskCommand
                vUp?.post(tap: .cgSessionEventTap)
                CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)?.post(tap: .cgSessionEventTap)
                vlog("Paste attempted")
            }
        }
    } catch {
        vlog("Error: \(error)")
    }
}

// MARK: - History Window (Photo viewer layout)

var historyWindow: NSWindow?
var historyRecords: [UploadRecord] = []
var historyCountLabel: NSTextField?
var historyPreviewImage: NSImageView?
var historyURLLabel: NSTextField?
var historyInfoLabel: NSTextField?
var historyThumbStrip: NSScrollView?
var historySelectedIndex: Int = 0
var historyImageCache: [String: NSImage] = [:]
let menuActions = MenuActions()

class ThumbItemView: NSView {
    var recordIndex: Int = 0

    @objc func clicked(_ gesture: NSClickGestureRecognizer) {
        selectHistoryImage(index: recordIndex)
    }
}

class ScaledImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image = self.image else { return }
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        // Calculate aspect-fit rect (centered, no distortion)
        let scaleX = bounds.width / imgSize.width
        let scaleY = bounds.height / imgSize.height
        let scale = min(scaleX, scaleY)
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let drawX = bounds.origin.x + (bounds.width - drawW) / 2
        let drawY = bounds.origin.y + (bounds.height - drawH) / 2

        image.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

func showHistoryWindow() {
    loadRecords()

    if let w = historyWindow {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    w.title = "VPaste 历史记录"
    w.minSize = NSSize(width: 600, height: 400)
    w.isReleasedWhenClosed = false
    w.center()

    guard let cv = w.contentView else { return }

    // --- Toolbar ---
    let toolbar = NSView()
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(toolbar)

    let refreshBtn = NSButton(title: "刷新", target: menuActions, action: #selector(MenuActions.refresh))
    refreshBtn.bezelStyle = .rounded
    refreshBtn.translatesAutoresizingMaskIntoConstraints = false
    toolbar.addSubview(refreshBtn)

    historyCountLabel = NSTextField(labelWithString: "")
    historyCountLabel!.font = NSFont.systemFont(ofSize: 12)
    historyCountLabel!.textColor = .secondaryLabelColor
    historyCountLabel!.translatesAutoresizingMaskIntoConstraints = false
    toolbar.addSubview(historyCountLabel!)

    // --- Right sidebar (info + copy button) ---
    let sidebar = NSView()
    sidebar.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(sidebar)

    let copyBtn = NSButton(title: "复制链接", target: menuActions, action: #selector(MenuActions.copySelectedURL))
    copyBtn.bezelStyle = .rounded
    copyBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    copyBtn.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(copyBtn)

    historyURLLabel = NSTextField(labelWithString: "")
    historyURLLabel!.font = NSFont.systemFont(ofSize: 11)
    historyURLLabel!.textColor = .secondaryLabelColor
    historyURLLabel!.lineBreakMode = .byTruncatingMiddle
    historyURLLabel!.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(historyURLLabel!)

    historyInfoLabel = NSTextField(labelWithString: "")
    historyInfoLabel!.font = NSFont.systemFont(ofSize: 11)
    historyInfoLabel!.textColor = .tertiaryLabelColor
    historyInfoLabel!.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(historyInfoLabel!)

    NSLayoutConstraint.activate([
        copyBtn.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
        copyBtn.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
        copyBtn.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
        copyBtn.heightAnchor.constraint(equalToConstant: 32),
        historyURLLabel!.topAnchor.constraint(equalTo: copyBtn.bottomAnchor, constant: 16),
        historyURLLabel!.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
        historyURLLabel!.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
        historyInfoLabel!.topAnchor.constraint(equalTo: historyURLLabel!.bottomAnchor, constant: 8),
        historyInfoLabel!.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
        historyInfoLabel!.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
    ])

    // --- Main preview area ---
    let previewContainer = NSView()
    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(previewContainer)

    historyPreviewImage = ScaledImageView()
    historyPreviewImage!.imageScaling = .scaleProportionallyUpOrDown
    historyPreviewImage!.imageAlignment = .alignCenter
    historyPreviewImage!.translatesAutoresizingMaskIntoConstraints = false
    previewContainer.addSubview(historyPreviewImage!)

    NSLayoutConstraint.activate([
        historyPreviewImage!.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
        historyPreviewImage!.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
        historyPreviewImage!.topAnchor.constraint(equalTo: previewContainer.topAnchor),
        historyPreviewImage!.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
    ])

    // --- Bottom thumbnail strip ---
    let thumbScroll = NSScrollView()
    thumbScroll.translatesAutoresizingMaskIntoConstraints = false
    thumbScroll.hasHorizontalScroller = true
    thumbScroll.autohidesScrollers = true
    thumbScroll.drawsBackground = false
    cv.addSubview(thumbScroll)
    historyThumbStrip = thumbScroll

    let thumbContainer = NSView()
    thumbScroll.documentView = thumbContainer

    // --- Layout with Auto Layout ---
    NSLayoutConstraint.activate([
        toolbar.topAnchor.constraint(equalTo: cv.topAnchor),
        toolbar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
        toolbar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        toolbar.heightAnchor.constraint(equalToConstant: 36),
        refreshBtn.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
        refreshBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        historyCountLabel!.leadingAnchor.constraint(equalTo: refreshBtn.trailingAnchor, constant: 10),
        historyCountLabel!.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

        // Sidebar on the right
        sidebar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
        sidebar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        sidebar.widthAnchor.constraint(equalToConstant: 200),
        sidebar.bottomAnchor.constraint(equalTo: thumbScroll.topAnchor),

        // Preview takes remaining space
        previewContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
        previewContainer.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
        previewContainer.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
        previewContainer.bottomAnchor.constraint(equalTo: thumbScroll.topAnchor),

        // Thumbnail strip at bottom
        thumbScroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
        thumbScroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        thumbScroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        thumbScroll.heightAnchor.constraint(equalToConstant: 110),
    ])

    historyWindow = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.async {
        rebuildHistoryUI()
    }
}

func rebuildHistoryUI() {
    guard let thumbContainer = historyThumbStrip?.documentView else { return }
    thumbContainer.subviews.forEach { $0.removeFromSuperview() }

    let thumbSize: CGFloat = 80
    let padding: CGFloat = 8
    let totalCount = historyRecords.count

    for (index, record) in historyRecords.enumerated() {
        let x = CGFloat(index) * (thumbSize + padding) + padding
        let item = ThumbItemView(frame: NSRect(x: x, y: 8, width: thumbSize, height: thumbSize + 20))
        item.recordIndex = index

        let imgView = NSImageView()
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.imageAlignment = .alignCenter
        imgView.wantsLayer = true
        imgView.layer?.cornerRadius = 4
        imgView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        imgView.frame = NSRect(x: 0, y: 18, width: thumbSize, height: thumbSize)
        item.addSubview(imgView)

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let label = NSTextField(labelWithString: fmt.string(from: record.uploaded_at))
        label.font = NSFont.systemFont(ofSize: 9)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: thumbSize, height: 14)
        item.addSubview(label)

        if let cached = historyImageCache[record.cdn_url] {
            imgView.image = cached
        } else if let url = URL(string: record.cdn_url) {
            let task = URLSession.shared.dataTask(with: url) { [weak imgView] data, _, _ in
                guard let data = data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    historyImageCache[record.cdn_url] = img
                    imgView?.image = img
                }
            }
            task.resume()
        }

        let clickGesture = NSClickGestureRecognizer(target: item, action: #selector(ThumbItemView.clicked(_:)))
        item.addGestureRecognizer(clickGesture)
        thumbContainer.addSubview(item)
    }

    let totalW = CGFloat(totalCount) * (thumbSize + padding) + padding
    thumbContainer.frame.size = NSSize(width: totalW, height: thumbSize + 28)

    if totalCount > 0 {
        selectHistoryImage(index: 0)
    }

    historyCountLabel?.stringValue = "共 \(totalCount) 张图片"
}

func selectHistoryImage(index: Int) {
    guard index >= 0, index < historyRecords.count else { return }
    historySelectedIndex = index
    let record = historyRecords[index]

    // Update preview
    if let cached = historyImageCache[record.cdn_url] {
        historyPreviewImage?.image = cached
    } else if let url = URL(string: record.cdn_url) {
        historyPreviewImage?.image = nil
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                historyImageCache[record.cdn_url] = img
                if historySelectedIndex == index {
                    historyPreviewImage?.image = img
                }
            }
        }
        task.resume()
    }

    // Update info
    historyURLLabel?.stringValue = record.cdn_url
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    historyInfoLabel?.stringValue = "大小: \(formatBytesHistory(record.size))\n时间: \(fmt.string(from: record.uploaded_at))"
}

func formatBytesHistory(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
    return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
}

func loadRecords() {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vpaste/records.json").path

    guard let data = FileManager.default.contents(atPath: path) else {
        historyRecords = []
        DispatchQueue.main.async { rebuildHistoryUI() }
        return
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
        let db = try decoder.decode(RecordsDB.self, from: data)
        historyRecords = Array(db.records.suffix(100).reversed())
    } catch {
        vlog("Failed to decode records: \(error)")
        historyRecords = []
    }

    DispatchQueue.main.async { rebuildHistoryUI() }
}

// MARK: - YAML Config

struct VPasteConfig {
    var provider: String = "cos"
    var secretID: String = ""
    var secretKey: String = ""
    var token: String = ""
    var bucket: String = ""
    var region: String = "ap-shanghai"
    var endpoint: String = ""
    var forcePathStyle: Bool = false
    var cdnDomain: String = ""
    var uploadPath: String = "vpaste/temp"
    var tempRetentionHours: Int = 24
}

func configFilePath() -> String {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vpaste/config.yaml").path
}

func loadVPasteConfig() -> VPasteConfig {
    var cfg = VPasteConfig()
    guard let data = FileManager.default.contents(atPath: configFilePath()),
          let content = String(data: data, encoding: .utf8) else {
        return cfg
    }
    for line in content.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), trimmed.contains(":") else { continue }
        let parts = trimmed.components(separatedBy: ":")
        guard parts.count >= 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let val = parts.dropFirst().joined(separator: ":")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        switch key {
        case "provider": cfg.provider = val
        case "secret_id": cfg.secretID = val
        case "secret_key": cfg.secretKey = val
        case "token": cfg.token = val
        case "bucket": cfg.bucket = val
        case "region": cfg.region = val
        case "endpoint": cfg.endpoint = val
        case "force_path_style": cfg.forcePathStyle = (val == "true")
        case "cdn_domain": cfg.cdnDomain = val
        case "upload_path": cfg.uploadPath = val
        case "temp_retention_hours":
            if let n = Int(val) { cfg.tempRetentionHours = n }
        default: break
        }
    }
    return cfg
}

func saveVPasteConfig(_ cfg: VPasteConfig) -> Bool {
    var lines: [String] = []
    lines.append("provider: \"\(cfg.provider)\"")
    lines.append("secret_id: \"\(cfg.secretID)\"")
    lines.append("secret_key: \"\(cfg.secretKey)\"")
    if !cfg.token.isEmpty { lines.append("token: \"\(cfg.token)\"") }
    lines.append("bucket: \"\(cfg.bucket)\"")
    if !cfg.region.isEmpty { lines.append("region: \"\(cfg.region)\"") }
    if !cfg.endpoint.isEmpty { lines.append("endpoint: \"\(cfg.endpoint)\"") }
    if cfg.forcePathStyle { lines.append("force_path_style: true") }
    if !cfg.cdnDomain.isEmpty { lines.append("cdn_domain: \"\(cfg.cdnDomain)\"") }
    lines.append("upload_path: \"\(cfg.uploadPath)\"")
    lines.append("temp_retention_hours: \(cfg.tempRetentionHours)")
    let content = lines.joined(separator: "\n") + "\n"
    let path = configFilePath()
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    do {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    } catch {
        vlog("Failed to save config: \(error)")
        return false
    }
}

// MARK: - Settings Window

var settingsWindow: NSWindow?

func showSettingsWindow() {
    if let w = settingsWindow {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let cfg = loadVPasteConfig()

    let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    w.title = "VPaste 设置"
    w.isReleasedWhenClosed = false
    w.center()

    guard let cv = w.contentView else { return }

    var currentY: CGFloat = 520
    let labelWidth: CGFloat = 100
    let fieldX: CGFloat = 120
    let fieldWidth: CGFloat = 350
    let rowHeight: CGFloat = 24
    let rowGap: CGFloat = 6

    func addSection(_ title: String) {
        currentY -= 16
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            line.topAnchor.constraint(equalTo: cv.topAnchor, constant: -currentY + 2),
        ])
        currentY -= 4
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.frame = NSRect(x: 16, y: currentY, width: 460, height: 14)
        cv.addSubview(label)
        currentY -= 20
    }

    func addRow(_ title: String, secure: Bool = false, placeholder: String = "") -> NSTextField {
        currentY -= rowGap
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .right
        label.textColor = .labelColor
        label.frame = NSRect(x: 16, y: currentY, width: labelWidth - 4, height: rowHeight)
        cv.addSubview(label)

        let field: NSTextField
        if secure {
            field = NSSecureTextField(frame: NSRect(x: fieldX, y: currentY, width: fieldWidth, height: rowHeight))
        } else {
            field = NSTextField(frame: NSRect(x: fieldX, y: currentY, width: fieldWidth, height: rowHeight))
        }
        field.font = NSFont.systemFont(ofSize: 13)
        if !placeholder.isEmpty { field.placeholderString = placeholder }
        cv.addSubview(field)
        currentY -= rowHeight
        return field
    }

    addSection("存储服务")
    currentY -= rowGap
    let providerLabel = NSTextField(labelWithString: "服务商")
    providerLabel.font = NSFont.systemFont(ofSize: 13)
    providerLabel.alignment = .right
    providerLabel.textColor = .labelColor
    providerLabel.frame = NSRect(x: 16, y: currentY, width: labelWidth - 4, height: rowHeight)
    cv.addSubview(providerLabel)

    let providerPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: currentY, width: fieldWidth, height: rowHeight))
    providerPopup.addItems(withTitles: ["腾讯云 COS", "AWS S3", "MinIO / S3 兼容"])
    providerPopup.lastItem?.representedObject = "cos"
    providerPopup.item(at: 1)?.representedObject = "s3"
    providerPopup.item(at: 2)?.representedObject = "minio"
    let providers = ["cos", "s3", "minio"]
    if let idx = providers.firstIndex(of: cfg.provider) {
        providerPopup.selectItem(at: idx)
    }
    cv.addSubview(providerPopup)
    currentY -= rowHeight

    addSection("认证信息")
    let secretIDField = addRow("Access Key", placeholder: "AKID...")
    secretIDField.stringValue = cfg.secretID
    let secretKeyField = addRow("Secret Key", secure: true, placeholder: "••••••••")
    secretKeyField.stringValue = cfg.secretKey
    let tokenField = addRow("Session Token", placeholder: "临时凭证时填写")
    tokenField.stringValue = cfg.token
    let bucketField = addRow("存储桶", placeholder: "my-bucket")
    bucketField.stringValue = cfg.bucket

    addSection("连接配置")
    let endpointField = addRow("Endpoint", placeholder: "https://s3.amazonaws.com")
    endpointField.stringValue = cfg.endpoint
    let regionField = addRow("Region", placeholder: "ap-shanghai")
    regionField.stringValue = cfg.region
    currentY -= rowGap
    let pathStyleCheck = NSButton(checkboxWithTitle: "使用路径样式 (MinIO 需要)", target: nil, action: nil)
    pathStyleCheck.font = NSFont.systemFont(ofSize: 13)
    pathStyleCheck.frame = NSRect(x: fieldX, y: currentY, width: fieldWidth, height: rowHeight)
    pathStyleCheck.state = cfg.forcePathStyle ? .on : .off
    cv.addSubview(pathStyleCheck)
    currentY -= rowHeight

    addSection("上传配置")
    let uploadPathField = addRow("上传路径", placeholder: "vpaste/temp")
    uploadPathField.stringValue = cfg.uploadPath
    let cdnDomainField = addRow("CDN 域名", placeholder: "可选")
    cdnDomainField.stringValue = cfg.cdnDomain

    addSection("自动清理")
    let retentionField = addRow("保留时间(小时)", placeholder: "24")
    retentionField.stringValue = "\(cfg.tempRetentionHours)"

    currentY -= 20
    let buttonY = currentY

    let saveBtn = NSButton(title: "保存", target: menuActions, action: #selector(MenuActions.saveSettings))
    saveBtn.bezelStyle = .rounded
    saveBtn.frame = NSRect(x: 380, y: buttonY, width: 80, height: 28)
    cv.addSubview(saveBtn)

    let cancelBtn = NSButton(title: "取消", target: menuActions, action: #selector(MenuActions.closeSettings))
    cancelBtn.bezelStyle = .rounded
    cancelBtn.frame = NSRect(x: 290, y: buttonY, width: 80, height: 28)
    cv.addSubview(cancelBtn)

    let testBtn = NSButton(title: "测试连接", target: menuActions, action: #selector(MenuActions.testConnection))
    testBtn.bezelStyle = .rounded
    testBtn.frame = NSRect(x: 20, y: buttonY, width: 90, height: 28)
    cv.addSubview(testBtn)

    let fields = SettingsFields()
    fields.providerPopup = providerPopup
    fields.secretIDField = secretIDField
    fields.secretKeyField = secretKeyField
    fields.tokenField = tokenField
    fields.bucketField = bucketField
    fields.endpointField = endpointField
    fields.regionField = regionField
    fields.pathStyleCheck = pathStyleCheck
    fields.uploadPathField = uploadPathField
    fields.cdnDomainField = cdnDomainField
    fields.retentionField = retentionField
    fields.window = w
    objc_setAssociatedObject(w, "fields", fields, .OBJC_ASSOCIATION_RETAIN)

    settingsWindow = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

class SettingsFields: NSObject {
    weak var providerPopup: NSPopUpButton?
    weak var secretIDField: NSTextField?
    weak var secretKeyField: NSTextField?
    weak var tokenField: NSTextField?
    weak var bucketField: NSTextField?
    weak var endpointField: NSTextField?
    weak var regionField: NSTextField?
    weak var pathStyleCheck: NSButton?
    weak var uploadPathField: NSTextField?
    weak var cdnDomainField: NSTextField?
    weak var retentionField: NSTextField?
    weak var window: NSWindow?
}

// MARK: - Carbon Global Hotkey (Cmd+Alt+V)

var hotkeyRef: EventHotKeyRef?

private let kVK_ANSI_V: UInt32 = 9

func hotkeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var hotkeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
    if hotkeyID.id == 1 {
        DispatchQueue.main.async { runVPaste() }
    }
    return noErr
}

func setupCarbonHotkey() {
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &eventType, nil, nil)

    let signature: OSType = 0x56505354 // "VPST"
    let hotkeyID = EventHotKeyID(signature: signature, id: 1)
    RegisterEventHotKey(kVK_ANSI_V, UInt32(cmdKey | optionKey), hotkeyID,
                        GetApplicationEventTarget(), 0, &hotkeyRef)
    vlog("Carbon hotkey registered: Cmd+Option+V")
}

func unregisterCarbonHotkey() {
    if let ref = hotkeyRef {
        UnregisterEventHotKey(ref)
        hotkeyRef = nil
    }
}

// MARK: - Accessibility Permission Check

var authWindow: NSWindow?
var accessibilityPollTimer: Timer?

func checkAccessibility() {
    if AXIsProcessTrusted() {
        vlog("Accessibility: already trusted")
        setupCarbonHotkey()
        return
    }

    vlog("Accessibility: not trusted, showing authorization window")
    showAuthWindow()

    accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
        if AXIsProcessTrusted() {
            timer.invalidate()
            accessibilityPollTimer = nil
            vlog("Accessibility: granted!")
            DispatchQueue.main.async {
                authWindow?.close()
                authWindow = nil
                setupCarbonHotkey()
            }
        }
    }
}

func showAuthWindow() {
    if let w = authWindow {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    w.title = "VPaste 需要辅助功能权限"
    w.isReleasedWhenClosed = false
    w.center()

    guard let cv = w.contentView else { return }

    let desc = NSTextField(labelWithString:
        "VPaste 需要辅助功能权限来监听全局快捷键 (Cmd+Option+V)。\n\n请在系统设置中授权后，快捷键将自动激活。")
    desc.font = NSFont.systemFont(ofSize: 13)
    desc.textColor = .labelColor
    desc.frame = NSRect(x: 24, y: 110, width: 372, height: 80)
    desc.isEditable = false
    desc.isSelectable = false
    cv.addSubview(desc)

    let openBtn = NSButton(title: "打开系统设置", target: menuActions, action: #selector(MenuActions.openAccessibilitySettings))
    openBtn.bezelStyle = .rounded
    openBtn.frame = NSRect(x: 24, y: 60, width: 160, height: 32)
    cv.addSubview(openBtn)

    let statusLabel = NSTextField(labelWithString: "等待授权...")
    statusLabel.font = NSFont.systemFont(ofSize: 12)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.frame = NSRect(x: 200, y: 68, width: 200, height: 18)
    cv.addSubview(statusLabel)

    let laterBtn = NSButton(title: "稍后再说", target: menuActions, action: #selector(MenuActions.dismissAuthWindow))
    laterBtn.bezelStyle = .rounded
    laterBtn.frame = NSRect(x: 24, y: 20, width: 100, height: 28)
    cv.addSubview(laterBtn)

    authWindow = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

// MARK: - Menu Actions

class MenuActions: NSObject, NSMenuDelegate {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { return true }

    @objc func upload() {
        vlog("Manual upload triggered")
        DispatchQueue.global(qos: .userInitiated).async { runVPaste() }
    }

    @objc func history() { showHistoryWindow() }

    @objc func refresh() { loadRecords() }

    @objc func copySelectedURL() {
        guard historySelectedIndex < historyRecords.count else { return }
        let url = historyRecords[historySelectedIndex].cdn_url
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        vlog("Copied: \(url)")
    }

    @objc func clean7d() { DispatchQueue.global(qos: .userInitiated).async { runClean(hours: 168) } }

    @objc func clean3d() { DispatchQueue.global(qos: .userInitiated).async { runClean(hours: 72) } }

    @objc func clean1d() { DispatchQueue.global(qos: .userInitiated).async { runClean(hours: 24) } }

    @objc func openSettings() { showSettingsWindow() }

    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "VPaste 使用帮助"
        alert.informativeText = """
        快捷键: Cmd + Option + V
        截图或复制图片到剪贴板后，按快捷键即可上传并自动粘贴 CDN 地址。

        状态栏菜单:
        · 上传剪贴板图片 — 手动上传
        · 历史记录 — 查看上传记录（点击复制 URL）
        · 设置 — 配置云存储服务商
        · 清理图床 — 删除云端旧文件
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func dismissAuthWindow() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        authWindow?.close()
        authWindow = nil
    }

    @objc func closeSettings() { settingsWindow?.close() }

    @objc func saveSettings() {
        guard let w = settingsWindow,
              let fields = objc_getAssociatedObject(w, "fields") as? SettingsFields else { return }

        var cfg = VPasteConfig()
        if let popup = fields.providerPopup,
           let item = popup.selectedItem,
           let code = item.representedObject as? String {
            cfg.provider = code
        }
        cfg.secretID = fields.secretIDField?.stringValue ?? ""
        cfg.secretKey = fields.secretKeyField?.stringValue ?? ""
        cfg.token = fields.tokenField?.stringValue ?? ""
        cfg.bucket = fields.bucketField?.stringValue ?? ""
        cfg.endpoint = fields.endpointField?.stringValue ?? ""
        cfg.region = fields.regionField?.stringValue ?? ""
        cfg.forcePathStyle = fields.pathStyleCheck?.state == .on
        cfg.cdnDomain = fields.cdnDomainField?.stringValue ?? ""
        cfg.uploadPath = fields.uploadPathField?.stringValue ?? "vpaste/temp"
        cfg.tempRetentionHours = Int(fields.retentionField?.stringValue ?? "24") ?? 24

        if saveVPasteConfig(cfg) {
            vlog("Settings saved to \(configFilePath())")
            let alert = NSAlert()
            alert.messageText = "设置已保存"
            alert.informativeText = "配置已写入 config.yaml。\n重启 VPaste daemon 后生效。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = "无法写入配置文件，请检查文件权限。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    @objc func testConnection() {
        guard let w = settingsWindow,
              let fields = objc_getAssociatedObject(w, "fields") as? SettingsFields else { return }

        // Build config from fields (DO NOT save to disk)
        var cfg = VPasteConfig()
        if let popup = fields.providerPopup,
           let item = popup.selectedItem,
           let code = item.representedObject as? String {
            cfg.provider = code
        }
        cfg.secretID = fields.secretIDField?.stringValue ?? ""
        cfg.secretKey = fields.secretKeyField?.stringValue ?? ""
        cfg.token = fields.tokenField?.stringValue ?? ""
        cfg.bucket = fields.bucketField?.stringValue ?? ""
        cfg.endpoint = fields.endpointField?.stringValue ?? ""
        cfg.region = fields.regionField?.stringValue ?? ""
        cfg.forcePathStyle = fields.pathStyleCheck?.state == .on
        cfg.cdnDomain = fields.cdnDomainField?.stringValue ?? ""
        cfg.uploadPath = fields.uploadPathField?.stringValue ?? "vpaste/temp"

        // Write to temp file, test, then restore original
        let configPath = configFilePath()
        let originalData = FileManager.default.contents(atPath: configPath)
        let _ = saveVPasteConfig(cfg)

        let vpastePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/vpaste").path

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", "\(vpastePath) stats 2>&1"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            var output = "无法执行测试"
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? output
            } catch {
                output = "测试失败: \(error.localizedDescription)"
            }

            // Restore original config
            if let orig = originalData {
                try? orig.write(to: URL(fileURLWithPath: configPath))
            } else {
                try? FileManager.default.removeItem(atPath: configPath)
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                if task.terminationStatus == 0 {
                    alert.messageText = "连接成功"
                    alert.alertStyle = .informational
                } else {
                    alert.messageText = "连接失败"
                    alert.alertStyle = .warning
                }
                alert.informativeText = output
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Status bar icon
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
if let button = statusItem.button {
    let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        let bg = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16),
                              xRadius: 3.5, yRadius: 3.5)
        NSColor(red: 0.15, green: 0.47, blue: 0.82, alpha: 1.0).setFill()
        bg.fill()

        let v = NSBezierPath()
        v.windingRule = .evenOdd
        v.move(to: NSPoint(x: 3, y: 14))
        v.line(to: NSPoint(x: 9, y: 3))
        v.line(to: NSPoint(x: 15, y: 14))
        v.close()
        v.move(to: NSPoint(x: 6, y: 14))
        v.line(to: NSPoint(x: 9, y: 6))
        v.line(to: NSPoint(x: 12, y: 14))
        v.close()
        NSColor.white.setFill()
        v.fill()
        return true
    }
    button.image = icon
    button.toolTip = "VPaste - Cmd+Alt+V"
}

let menu = NSMenu()

let uploadItem = NSMenuItem(title: "上传剪贴板图片", action: #selector(MenuActions.upload), keyEquivalent: "")
uploadItem.target = menuActions
menu.addItem(uploadItem)

let historyItem = NSMenuItem(title: "历史记录", action: #selector(MenuActions.history), keyEquivalent: "")
historyItem.target = menuActions
menu.addItem(historyItem)

let settingsItem = NSMenuItem(title: "设置...", action: #selector(MenuActions.openSettings), keyEquivalent: ",")
settingsItem.target = menuActions
menu.addItem(settingsItem)

let cleanMenu = NSMenu()
cleanMenu.delegate = menuActions

let clean7d = NSMenuItem(title: "7 天前上传的", action: #selector(MenuActions.clean7d), keyEquivalent: "")
clean7d.target = menuActions
cleanMenu.addItem(clean7d)

let clean3d = NSMenuItem(title: "3 天前上传的", action: #selector(MenuActions.clean3d), keyEquivalent: "")
clean3d.target = menuActions
cleanMenu.addItem(clean3d)

let clean1d = NSMenuItem(title: "1 天前上传的", action: #selector(MenuActions.clean1d), keyEquivalent: "")
clean1d.target = menuActions
cleanMenu.addItem(clean1d)

let cleanItem = NSMenuItem(title: "清理图床", action: nil, keyEquivalent: "")
cleanItem.submenu = cleanMenu
menu.addItem(cleanItem)

menu.addItem(.separator())

let helpItem = NSMenuItem(title: "使用帮助", action: #selector(MenuActions.showHelp), keyEquivalent: "")
helpItem.target = menuActions
menu.addItem(helpItem)

menu.addItem(withTitle: "退出 VPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.delegate = menuActions
statusItem.menu = menu

checkAccessibility()

Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in }

vlog("Daemon started")

atexit { unregisterCarbonHotkey() }

app.run()
