import Cocoa
import Carbon

let vpastePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/bin/vpaste").path

NSLog("VPaste: vpaste path = \(vpastePath)")

func pasteURL(_ url: String) {
    NSLog("VPaste: Pasting URL: \(url)")

    let pasteboard = NSPasteboard.general

    // Set URL to clipboard
    pasteboard.clearContents()
    pasteboard.setString(url, forType: .string)

    // Simulate Cmd+V after small delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd down
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.post(tap: .cgSessionEventTap)

        // V down
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)

        // V up
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cgSessionEventTap)

        // Cmd up
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cgSessionEventTap)

        NSLog("VPaste: Paste completed")
    }
}

func runVPaste() {
    NSLog("VPaste: Starting vpaste execution...")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", vpastePath]

    let stdoutPipe = Pipe()
    task.standardOutput = stdoutPipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let status = task.terminationStatus
        NSLog("VPaste: vpaste exited with status \(status), output: \(output)")

        if output == "NO_IMAGE" || output.isEmpty {
            NSLog("VPaste: No image in clipboard")
        } else {
            pasteURL(output)
        }
    } catch {
        NSLog("VPaste: Error running vpaste - \(error)")
    }
}

// CGEventTap callback
func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let isCmd = flags.contains(.maskCommand)
        let isAlt = flags.contains(.maskAlternate)
        let isV = keyCode == 9

        if isV && isCmd && isAlt {
            NSLog("VPaste: Cmd+Alt+V detected!")
            // Run asynchronously to not block the event tap
            DispatchQueue.main.async {
                runVPaste()
            }
            return nil // Consume the event
        }
    }
    return Unmanaged.passRetained(event)
}

func setupEventTap() -> Bool {
    let eventMask = (1 << CGEventType.keyDown.rawValue)

    guard let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: eventTapCallback,
        userInfo: nil
    ) else {
        NSLog("VPaste: Failed to create event tap")
        return false
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    NSLog("VPaste: EventTap created and enabled")
    return true
}

// Main
NSLog("VPaste daemon starting...")

if !setupEventTap() {
    NSLog("VPaste: Failed to setup keyboard monitoring")
}

NSLog("VPaste: Listening for Cmd+Alt+V...")

RunLoop.main.run()