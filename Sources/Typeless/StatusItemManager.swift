import Cocoa

public enum AppStatus {
    case idle
    case recording(isCleaned: Bool)
    case transcribing
    case cleaning
    case needsAccessibility
    case error(String)
}

public final class StatusItemManager: NSObject, NSMenuDelegate {
    public static let shared = StatusItemManager()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var currentStatus: AppStatus = .idle

    private override init() {
        super.init()
    }

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
        updateStatus(trusted ? .idle : .needsAccessibility)
        rebuildMenu()

        // Listen for history updates
        HistoryLogger.shared.onHistoryUpdated = { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    public func updateStatus(_ status: AppStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            self.currentStatus = status

            switch status {
            case .idle:
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Typeless Idle")
                button.image?.isTemplate = true
                button.title = ""
                button.toolTip = "Typeless: Ready (Hold Right Option to speak)"

            case .recording(let isCleaned):
                button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
                button.image?.isTemplate = false
                button.title = isCleaned ? " 🔴 REC (Clean)" : " 🔴 REC"
                button.toolTip = "Typeless: Recording mic... (Release to paste)"

            case .transcribing:
                button.image = NSImage(systemSymbolName: "waveform.badge.magnifyingglass", accessibilityDescription: "Transcribing")
                button.image?.isTemplate = true
                button.title = " ⏳ Transcribing..."
                button.toolTip = "Typeless: Transcribing locally via whisper.cpp..."

            case .cleaning:
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Polishing")
                button.image?.isTemplate = true
                button.title = " ✨ Polishing..."
                button.toolTip = "Typeless: Cleaning punctuation and filler words via LLM..."

            case .needsAccessibility:
                button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Needs Permission")
                button.image?.isTemplate = false
                button.title = " ⚠️ Needs Permission"
                button.toolTip = "Typeless: Accessibility permission required (Click menu to enable)"

            case .error(let msg):
                button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
                button.image?.isTemplate = false
                button.title = " ⚠️"
                button.toolTip = "Typeless Error: \(msg)"
            }
        }
    }

    public func rebuildMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.menu.removeAllItems()

            let config = ConfigManager.shared.config
            let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)

            // Permission Warning Banner if not trusted
            if !trusted {
                let warnItem = NSMenuItem(title: "⚠️ Accessibility Permission Required", action: #selector(self.checkPermissions), keyEquivalent: "")
                warnItem.target = self
                let attrTitle = NSAttributedString(
                    string: "⚠️ Accessibility Not Granted (Click to Enable)",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 12),
                        .foregroundColor: NSColor.systemRed
                    ]
                )
                warnItem.attributedTitle = attrTitle
                self.menu.addItem(warnItem)
                self.menu.addItem(NSMenuItem.separator())
            }

            // 1. App Title & Status
            let titleItem = NSMenuItem(title: "Typeless — Offline Dictation", action: nil, keyEquivalent: "")
            let titleFont = NSFont.boldSystemFont(ofSize: 13)
            titleItem.attributedTitle = NSAttributedString(string: "Typeless — Offline Dictation", attributes: [.font: titleFont])
            self.menu.addItem(titleItem)

            let hotkeyInfo = "Standard: Hold [\(config.standardHotkey)]  •  Cleaned: Hold [\(config.cleanupHotkey)]"
            let subInfoItem = NSMenuItem(title: hotkeyInfo, action: nil, keyEquivalent: "")
            subInfoItem.isEnabled = false
            self.menu.addItem(subInfoItem)

            // Model info
            let modelName = URL(fileURLWithPath: config.resolvedModelPath).lastPathComponent
            let modelExists = FileManager.default.fileExists(atPath: config.resolvedModelPath)
            let modelStatus = modelExists ? "Model: \(modelName) ✓" : "Model: \(modelName) (Missing!)"
            let modelItem = NSMenuItem(title: modelStatus, action: nil, keyEquivalent: "")
            modelItem.isEnabled = false
            self.menu.addItem(modelItem)

            // LLM API Key info
            let apiKeySet = ConfigManager.shared.getAPIKey() != nil
            let llmStatus = apiKeySet ? "LLM Cleanup: Configured (\(config.llmModel)) ✓" : "LLM Cleanup: Plain Paste (No API key in .env)"
            let llmItem = NSMenuItem(title: llmStatus, action: nil, keyEquivalent: "")
            llmItem.isEnabled = false
            self.menu.addItem(llmItem)

            self.menu.addItem(NSMenuItem.separator())

            // 2. Recent Transcripts Section
            let recentHeader = NSMenuItem(title: "Recent Transcripts (Click to Copy):", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            self.menu.addItem(recentHeader)

            let records = HistoryLogger.shared.recentRecords
            if records.isEmpty {
                let emptyItem = NSMenuItem(title: "  (No transcripts yet)", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                self.menu.addItem(emptyItem)
            } else {
                for record in records {
                    let cleanTag = record.isCleaned ? " [Clean]" : ""
                    let itemTitle = "  [\(record.formattedTime)]\(cleanTag) \"\(record.summary)\""
                    let item = NSMenuItem(title: itemTitle, action: #selector(self.copyTranscriptItemClicked(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = record
                    item.toolTip = record.text
                    self.menu.addItem(item)
                }
            }

            self.menu.addItem(NSMenuItem.separator())

            // 3. Quick Actions
            let dictationFolderItem = NSMenuItem(title: "Open Dictation Folder (~/Dictation)", action: #selector(self.openDictationFolder), keyEquivalent: "d")
            dictationFolderItem.target = self
            self.menu.addItem(dictationFolderItem)

            let configFolderItem = NSMenuItem(title: "Open Config Folder (~/.config/typeless)", action: #selector(self.openConfigFolder), keyEquivalent: "c")
            configFolderItem.target = self
            self.menu.addItem(configFolderItem)

            let logItem = NSMenuItem(title: "View Application Log (typeless.log)", action: #selector(self.openLogFile), keyEquivalent: "l")
            logItem.target = self
            self.menu.addItem(logItem)

            let permissionsItem = NSMenuItem(title: "Check System Permissions...", action: #selector(self.checkPermissions), keyEquivalent: "p")
            permissionsItem.target = self
            self.menu.addItem(permissionsItem)

            let reloadItem = NSMenuItem(title: "Reload Config & .env", action: #selector(self.reloadConfig), keyEquivalent: "r")
            reloadItem.target = self
            self.menu.addItem(reloadItem)

            self.menu.addItem(NSMenuItem.separator())

            // 4. Quit
            let quitItem = NSMenuItem(title: "Quit Typeless", action: #selector(self.quitApp), keyEquivalent: "q")
            quitItem.target = self
            self.menu.addItem(quitItem)
        }
    }

    @objc private func copyTranscriptItemClicked(_ sender: NSMenuItem) {
        if let record = sender.representedObject as? TranscriptRecord {
            HistoryLogger.shared.copyRecordToClipboard(record)
            let alert = NSAlert()
            alert.messageText = "Transcript Copied"
            alert.informativeText = "Copied to clipboard:\n\n\"\(record.text)\""
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    @objc private func openDictationFolder() {
        let folder = ConfigManager.shared.config.resolvedDictationFolder
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }

    @objc private func openConfigFolder() {
        let folder = ConfigManager.shared.configDirectory.path
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }

    @objc private func openLogFile() {
        let logPath = LogManager.shared.logPath
        if FileManager.default.fileExists(atPath: logPath) {
            NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: (logPath as NSString).deletingLastPathComponent)
        }
    }

    @objc private func checkPermissions() {
        let hasAccessibility = KeyMonitor.isAccessibilityTrusted(prompt: true)
        if hasAccessibility {
            let alert = NSAlert()
            alert.messageText = "System Permissions Status"
            alert.informativeText = "✓ Accessibility: Granted\n✓ Push-to-talk hotkeys are active.\n\nMicrophone access will be prompted automatically by macOS on your first recording."
            alert.alertStyle = .informational
            alert.runModal()
            self.updateStatus(.idle)
            self.rebuildMenu()
        } else {
            KeyMonitor.openAccessibilitySettings()
        }
    }

    @objc private func reloadConfig() {
        ConfigManager.shared.reload()
        rebuildMenu()
        let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
        updateStatus(trusted ? .idle : .needsAccessibility)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
