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
            // Copy URL to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)

            // Try auto-paste via CGEvent
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

// MARK: - History Window

var historyWindow: NSWindow?
var historyTable: NSTableView?
var historyRecords: [UploadRecord] = []
var historyCountLabel: NSTextField?
let menuActions = MenuActions()

func showHistoryWindow() {
    loadRecords()

    if let w = historyWindow {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    w.title = "VPaste 历史记录"
    w.minSize = NSSize(width: 500, height: 300)
    w.center()

    guard let cv = w.contentView else { return }

    // Toolbar
    let toolbar = NSView()
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(toolbar)

    let refreshBtn = NSButton(title: "刷新", target: nil, action: nil)
    refreshBtn.bezelStyle = .rounded
    refreshBtn.translatesAutoresizingMaskIntoConstraints = false
    refreshBtn.target = menuActions
    refreshBtn.action = #selector(MenuActions.refresh)
    toolbar.addSubview(refreshBtn)

    historyCountLabel = NSTextField(labelWithString: "")
    historyCountLabel!.font = NSFont.systemFont(ofSize: 12)
    historyCountLabel!.textColor = .secondaryLabelColor
    historyCountLabel!.translatesAutoresizingMaskIntoConstraints = false
    toolbar.addSubview(historyCountLabel!)

    // Table
    let table = NSTableView()
    table.usesAlternatingRowBackgroundColors = true
    table.rowHeight = 28

    let timeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
    timeCol.title = "时间"
    timeCol.width = 140
    table.addTableColumn(timeCol)

    let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
    sizeCol.title = "大小"
    sizeCol.width = 70
    table.addTableColumn(sizeCol)

    let urlCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
    urlCol.title = "URL"
    urlCol.width = 380
    table.addTableColumn(urlCol)

    let copyCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("copy"))
    copyCol.title = ""
    copyCol.width = 60
    table.addTableColumn(copyCol)

    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    cv.addSubview(scroll)

    NSLayoutConstraint.activate([
        toolbar.topAnchor.constraint(equalTo: cv.topAnchor),
        toolbar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
        toolbar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        toolbar.heightAnchor.constraint(equalToConstant: 40),
        refreshBtn.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
        refreshBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        historyCountLabel!.leadingAnchor.constraint(equalTo: refreshBtn.trailingAnchor, constant: 12),
        historyCountLabel!.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
        scroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
        scroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        scroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
    ])

    // Use a delegate class for table
    let delegate = HistoryDelegate()
    delegate.table = table
    delegate.window = w
    table.dataSource = delegate
    table.delegate = delegate
    objc_setAssociatedObject(table, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

    historyTable = table
    historyWindow = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

func loadRecords() {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vpaste/records.json").path

    guard let data = FileManager.default.contents(atPath: path) else {
        historyRecords = []
        historyTable?.reloadData()
        historyCountLabel?.stringValue = "共 0 条记录"
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

    historyTable?.reloadData()
    historyCountLabel?.stringValue = "共 \(historyRecords.count) 条记录"
}

// MARK: - History Table Delegate

class HistoryDelegate: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    weak var table: NSTableView?
    weak var window: NSWindow?

    func numberOfRows(in tableView: NSTableView) -> Int {
        return historyRecords.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < historyRecords.count else { return nil }
        let record = historyRecords[row]
        let columnID = tableColumn?.identifier.rawValue ?? ""

        switch columnID {
        case "time":
            let cell = makeCell(tableView: tableView, id: tableColumn!.identifier)
            let fmt = DateFormatter()
            fmt.dateFormat = "MM-dd HH:mm"
            cell.textField?.stringValue = fmt.string(from: record.uploaded_at)
            return cell
        case "size":
            let cell = makeCell(tableView: tableView, id: tableColumn!.identifier)
            cell.textField?.stringValue = formatBytes(record.size)
            return cell
        case "url":
            let cell = makeCell(tableView: tableView, id: tableColumn!.identifier)
            cell.textField?.stringValue = record.cdn_url
            cell.textField?.lineBreakMode = .byTruncatingMiddle
            return cell
        case "copy":
            let btn = NSButton(title: "复制", target: self, action: #selector(copyURL(_:)))
            btn.tag = row
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            return btn
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if row < historyRecords.count {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(historyRecords[row].cdn_url, forType: .string)
        }
        return false
    }

    @objc func copyURL(_ sender: NSButton) {
        let row = sender.tag
        guard row < historyRecords.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(historyRecords[row].cdn_url, forType: .string)
    }

    private func makeCell(tableView: NSTableView, id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        if let existing = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            return existing
        }
        let cell = NSTableCellView()
        cell.identifier = id
        let tf = NSTextField()
        tf.isBordered = false
        tf.isEditable = false
        tf.drawsBackground = false
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }
}

// MARK: - YAML Config (simple flat key-value)

struct VPasteConfig {
    var secretID: String = ""
    var secretKey: String = ""
    var token: String = ""
    var bucket: String = ""
    var region: String = "ap-shanghai"
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
        case "secret_id": cfg.secretID = val
        case "secret_key": cfg.secretKey = val
        case "token": cfg.token = val
        case "bucket": cfg.bucket = val
        case "region": cfg.region = val
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
    lines.append("secret_id: \"\(cfg.secretID)\"")
    lines.append("secret_key: \"\(cfg.secretKey)\"")
    if !cfg.token.isEmpty {
        lines.append("token: \"\(cfg.token)\"")
    }
    lines.append("bucket: \"\(cfg.bucket)\"")
    lines.append("region: \"\(cfg.region)\"")
    if !cfg.cdnDomain.isEmpty {
        lines.append("cdn_domain: \"\(cfg.cdnDomain)\"")
    }
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

let regionOptions = [
    ("ap-beijing", "北京"),
    ("ap-nanjing", "南京"),
    ("ap-shanghai", "上海"),
    ("ap-guangzhou", "广州"),
    ("ap-chengdu", "成都"),
    ("ap-chongqing", "重庆"),
    ("ap-hongkong", "中国香港"),
    ("ap-singapore", "新加坡"),
    ("ap-tokyo", "东京"),
    ("na-siliconvalley", "硅谷"),
    ("na-ashburn", "弗吉尼亚"),
    ("eu-frankfurt", "法兰克福"),
]

func showSettingsWindow() {
    if let w = settingsWindow {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let cfg = loadVPasteConfig()

    let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    w.title = "VPaste 设置"
    w.isReleasedWhenClosed = false
    w.center()

    guard let cv = w.contentView else { return }

    // --- Helper to create form rows ---
    var currentY: CGFloat = 420
    let labelWidth: CGFloat = 130
    let fieldX: CGFloat = 150
    let fieldWidth: CGFloat = 340
    let rowHeight: CGFloat = 28
    let sectionGap: CGFloat = 16
    let rowGap: CGFloat = 6

    func addSection(_ title: String) {
        currentY -= sectionGap
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: currentY, width: 480, height: 16)
        cv.addSubview(label)
        currentY -= 20
    }

    func addRow(_ title: String, secure: Bool = false) -> NSTextField {
        currentY -= rowGap
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .right
        label.frame = NSRect(x: 20, y: currentY, width: labelWidth - 8, height: rowHeight)
        cv.addSubview(label)

        let field: NSTextField
        if secure {
            let sf = NSSecureTextField(frame: NSRect(x: fieldX, y: currentY, width: fieldWidth, height: rowHeight))
            field = sf
        } else {
            field = NSTextField(frame: NSRect(x: fieldX, y: currentY, width: fieldWidth, height: rowHeight))
        }
        field.font = NSFont.systemFont(ofSize: 13)
        cv.addSubview(field)
        currentY -= rowHeight
        return field
    }

    // --- COS Section ---
    addSection("腾讯云 COS 配置")
    let secretIDField = addRow("Secret ID:")
    secretIDField.stringValue = cfg.secretID
    let secretKeyField = addRow("Secret Key:", secure: true)
    secretKeyField.stringValue = cfg.secretKey
    let tokenField = addRow("Token:")
    tokenField.stringValue = cfg.token
    let bucketField = addRow("存储桶:")
    bucketField.stringValue = cfg.bucket

    // Region popup
    currentY -= rowGap
    let regionLabel = NSTextField(labelWithString: "地域:")
    regionLabel.font = NSFont.systemFont(ofSize: 13)
    regionLabel.alignment = .right
    regionLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth - 8, height: rowHeight)
    cv.addSubview(regionLabel)

    let regionPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: currentY, width: fieldWidth, height: rowHeight))
    for (code, name) in regionOptions {
        regionPopup.addItem(withTitle: "\(code) (\(name))")
        regionPopup.lastItem?.representedObject = code
    }
    // Select current region
    if let idx = regionOptions.firstIndex(where: { $0.0 == cfg.region }) {
        regionPopup.selectItem(at: idx)
    }
    cv.addSubview(regionPopup)
    currentY -= rowHeight

    // --- Upload Section ---
    addSection("上传配置")
    let uploadPathField = addRow("上传路径:")
    uploadPathField.stringValue = cfg.uploadPath
    let cdnDomainField = addRow("CDN 域名:")
    cdnDomainField.stringValue = cfg.cdnDomain

    // --- Cleanup Section ---
    addSection("自动清理")
    let retentionField = addRow("保留时间(小时):")
    retentionField.stringValue = "\(cfg.tempRetentionHours)"

    // --- Buttons ---
    currentY -= 20
    let buttonY = currentY

    let saveBtn = NSButton(title: "保存", target: nil, action: #selector(MenuActions.saveSettings))
    saveBtn.bezelStyle = .rounded
    saveBtn.frame = NSRect(x: 380, y: buttonY, width: 80, height: 28)
    cv.addSubview(saveBtn)

    let cancelBtn = NSButton(title: "取消", target: nil, action: #selector(MenuActions.closeSettings))
    cancelBtn.bezelStyle = .rounded
    cancelBtn.frame = NSRect(x: 290, y: buttonY, width: 80, height: 28)
    cv.addSubview(cancelBtn)

    let testBtn = NSButton(title: "测试连接", target: nil, action: #selector(MenuActions.testConnection))
    testBtn.bezelStyle = .rounded
    testBtn.frame = NSRect(x: 20, y: buttonY, width: 90, height: 28)
    cv.addSubview(testBtn)

    // Store references for save
    let fields = SettingsFields()
    fields.secretIDField = secretIDField
    fields.secretKeyField = secretKeyField
    fields.tokenField = tokenField
    fields.bucketField = bucketField
    fields.regionPopup = regionPopup
    fields.uploadPathField = uploadPathField
    fields.cdnDomainField = cdnDomainField
    fields.retentionField = retentionField
    fields.window = w
    objc_setAssociatedObject(w, "fields", fields, .OBJC_ASSOCIATION_RETAIN)

    saveBtn.target = menuActions
    cancelBtn.target = menuActions
    testBtn.target = menuActions

    settingsWindow = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

class SettingsFields: NSObject {
    weak var secretIDField: NSTextField?
    weak var secretKeyField: NSTextField?
    weak var tokenField: NSTextField?
    weak var bucketField: NSTextField?
    weak var regionPopup: NSPopUpButton?
    weak var uploadPathField: NSTextField?
    weak var cdnDomainField: NSTextField?
    weak var retentionField: NSTextField?
    weak var window: NSWindow?
}

// MARK: - Carbon Global Hotkey (Cmd+Alt+V)

var hotkeyRef: EventHotKeyRef?

private let kVK_ANSI_V: UInt32 = 9
private let kVK_Command: UInt32 = 0x37

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
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }

    @objc func upload() {
        vlog("Manual upload triggered")
        DispatchQueue.global(qos: .userInitiated).async { runVPaste() }
    }

    @objc func history() {
        showHistoryWindow()
    }

    @objc func refresh() {
        loadRecords()
    }

    @objc func clean7d() {
        DispatchQueue.global(qos: .userInitiated).async { runClean(hours: 168) }
    }

    @objc func clean3d() {
        DispatchQueue.global(qos: .userInitiated).async { runClean(hours: 72) }
    }

    @objc func clean1d() {
        DispatchQueue.global(qos: .userInitiated).async { runClean(hours: 24) }
    }

    @objc func openSettings() {
        showSettingsWindow()
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

    @objc func closeSettings() {
        settingsWindow?.close()
    }

    @objc func saveSettings() {
        guard let w = settingsWindow,
              let fields = objc_getAssociatedObject(w, "fields") as? SettingsFields else { return }

        var cfg = VPasteConfig()
        cfg.secretID = fields.secretIDField?.stringValue ?? ""
        cfg.secretKey = fields.secretKeyField?.stringValue ?? ""
        cfg.token = fields.tokenField?.stringValue ?? ""
        cfg.bucket = fields.bucketField?.stringValue ?? ""
        cfg.cdnDomain = fields.cdnDomainField?.stringValue ?? ""
        cfg.uploadPath = fields.uploadPathField?.stringValue ?? "vpaste/temp"
        cfg.tempRetentionHours = Int(fields.retentionField?.stringValue ?? "24") ?? 24

        if let popup = fields.regionPopup,
           let item = popup.selectedItem,
           let code = item.representedObject as? String {
            cfg.region = code
        }

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

        // Temporarily save to test
        var cfg = VPasteConfig()
        cfg.secretID = fields.secretIDField?.stringValue ?? ""
        cfg.secretKey = fields.secretKeyField?.stringValue ?? ""
        cfg.token = fields.tokenField?.stringValue ?? ""
        cfg.bucket = fields.bucketField?.stringValue ?? ""
        cfg.cdnDomain = fields.cdnDomainField?.stringValue ?? ""
        cfg.uploadPath = fields.uploadPathField?.stringValue ?? "vpaste/temp"

        if let popup = fields.regionPopup,
           let item = popup.selectedItem,
           let code = item.representedObject as? String {
            cfg.region = code
        }

        // Save temp config and run vpaste stats
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
        // Blue gradient background
        let bg = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16),
                              xRadius: 3.5, yRadius: 3.5)
        NSColor(red: 0.15, green: 0.47, blue: 0.82, alpha: 1.0).setFill()
        bg.fill()

        // Hollow V — even-odd fill: overlap becomes transparent
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
menu.addItem(withTitle: "退出 VPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.delegate = menuActions
statusItem.menu = menu

// Check accessibility and register hotkey (like Rectangle)
checkAccessibility()

// Keep run loop active for Carbon event dispatch
Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in }

vlog("Daemon started")

atexit { unregisterCarbonHotkey() }

app.run()
