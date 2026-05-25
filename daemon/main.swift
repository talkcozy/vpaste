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

// MARK: - Carbon HotKey

var hotKeyRef: EventHotKeyRef?

private func hotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    refcon: UnsafeMutableRawPointer?
) -> OSStatus {
    vlog("HotKey pressed!")
    DispatchQueue.main.async { runVPaste() }
    return noErr
}

// MARK: - Menu Actions

class MenuActions: NSObject, NSMenuDelegate {
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
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Status bar icon
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
if let button = statusItem.button {
    button.title = "V"
    button.font = NSFont.boldSystemFont(ofSize: 14)
    button.toolTip = "VPaste - Cmd+Alt+V"
}

let menu = NSMenu()
menu.addItem(withTitle: "上传剪贴板图片", action: #selector(MenuActions.upload), keyEquivalent: "")
menu.addItem(withTitle: "历史记录", action: #selector(MenuActions.history), keyEquivalent: "")
menu.addItem(.separator())
menu.addItem(withTitle: "退出 VPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.delegate = menuActions
statusItem.menu = menu

// Carbon hotkey: Cmd+Alt+V
var eventSpec = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard),
    eventKind: UInt32(kEventHotKeyPressed)
)
InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &eventSpec, nil, nil)

var hkID = EventHotKeyID()
hkID.signature = OSType(0x56505354) // "VPST"
hkID.id = 1
let hkStatus = RegisterEventHotKey(
    0x09, // V key
    UInt32(cmdKey | optionKey),
    hkID,
    GetEventDispatcherTarget(),
    0,
    &hotKeyRef
)

vlog("Hotkey status: \(hkStatus)")
vlog("Daemon started - Cmd+Alt+V to upload")

RunLoop.main.run()
