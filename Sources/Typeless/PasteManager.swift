import AppKit
import Carbon

public final class PasteManager {
    public static let shared = PasteManager()

    private struct ClipboardItemSnapshot {
        let types: [NSPasteboard.PasteboardType: Data]
    }

    private var pendingRestoreItem: DispatchWorkItem?
    private let restoreQueue = DispatchQueue(label: "com.typeless.pastemanager.restore")

    private init() {}

    public func pasteAndRestore(text: String, delayMs: Int = 400) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // 1. Snapshot previous clipboard content
        let previousItems = snapshotClipboard(pasteboard)

        // 2. Put transcribed text into the clipboard
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)

        // Ensure pasteboard daemon commits the string before the keystroke reaches the app
        usleep(25_000) // 25ms

        // 3. Simulate Cmd+V keystroke
        simulateCommandV()

        // 4. Cancel any previous pending restore
        pendingRestoreItem?.cancel()

        // 5. Wait for the active app (especially Electron / browser apps) to consume the paste event
        let safeDelayMs = max(delayMs, 350)
        let delaySeconds = Double(safeDelayMs) / 1000.0

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.restoreClipboard(previousItems, to: pasteboard)
            LogManager.shared.log("Previous clipboard restored after \(safeDelayMs)ms delay.")
        }

        self.pendingRestoreItem = workItem
        restoreQueue.asyncAfter(deadline: .now() + delaySeconds, execute: workItem)
    }

    private func simulateCommandV() {
        let vKeyCode: CGKeyCode = 0x09 // virtual key code for 'v'
        let eventSource = CGEventSource(stateID: .combinedSessionState)

        if let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        } else {
            // Fallback via osascript if CGEvent cannot be created
            let script = "tell application \"System Events\" to keystroke \"v\" using command down"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }

    private func snapshotClipboard(_ pasteboard: NSPasteboard) -> [ClipboardItemSnapshot] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        var result: [ClipboardItemSnapshot] = []

        for item in items {
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            result.append(ClipboardItemSnapshot(types: dataByType))
        }

        return result
    }

    private func restoreClipboard(_ snapshots: [ClipboardItemSnapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if snapshots.isEmpty { return }

        var pasteboardItems: [NSPasteboardItem] = []
        for snapshot in snapshots {
            let item = NSPasteboardItem()
            for (type, data) in snapshot.types {
                item.setData(data, forType: type)
            }
            pasteboardItems.append(item)
        }

        pasteboard.writeObjects(pasteboardItems)
    }
}
