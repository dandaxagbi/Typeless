import Cocoa
import ServiceManagement

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
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Typeless")
                button.image?.isTemplate = true
                button.title = ""
                button.toolTip = "Typeless: Listo (Mantén pulsada Option Derecha)"

            case .recording(let isCleaned):
                button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Grabando")
                button.image?.isTemplate = false
                button.title = isCleaned ? " 🔴 REC (Limpio)" : " 🔴 REC"
                button.toolTip = "Typeless: Grabando micrófono..."

            case .transcribing:
                button.image = NSImage(systemSymbolName: "waveform.badge.magnifyingglass", accessibilityDescription: "Transcribiendo")
                button.image?.isTemplate = true
                button.title = " ⏳"
                button.toolTip = "Typeless: Transcribiendo audio..."

            case .cleaning:
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Pulir")
                button.image?.isTemplate = true
                button.title = " ✨"
                button.toolTip = "Typeless: Limpiando con IA..."

            case .needsAccessibility:
                button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Permisos requeridos")
                button.image?.isTemplate = false
                button.title = " ⚠️"
                button.toolTip = "Typeless: Requiere permisos de Accesibilidad"

            case .error(let msg):
                button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
                button.image?.isTemplate = false
                button.title = " ⚠️"
                button.toolTip = "Typeless: \(msg)"
            }
        }
    }

    public func rebuildMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.menu.removeAllItems()

            let config = ConfigManager.shared.config
            let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)

            // 1. Aviso de permisos (solo si faltan)
            if !trusted {
                let warnItem = NSMenuItem(title: "⚠️ Dar permisos de Accesibilidad...", action: #selector(self.checkPermissions), keyEquivalent: "")
                warnItem.target = self
                let attrTitle = NSAttributedString(
                    string: "⚠️ Activar permisos de Accesibilidad",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 12),
                        .foregroundColor: NSColor.systemRed
                    ]
                )
                warnItem.attributedTitle = attrTitle
                self.menu.addItem(warnItem)
                self.menu.addItem(NSMenuItem.separator())
            }

            // 2. Historial de transcripciones recientes
            let records = HistoryLogger.shared.recentRecords
            if records.isEmpty {
                let emptyItem = NSMenuItem(title: "Sin dictados recientes", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                self.menu.addItem(emptyItem)
            } else {
                for record in records {
                    let cleanTag = record.isCleaned ? " ✨" : ""
                    let itemTitle = "[\(record.formattedTime)]\(cleanTag) \"\(record.summary)\""
                    let item = NSMenuItem(title: itemTitle, action: #selector(self.copyTranscriptItemClicked(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = record
                    item.toolTip = "Clic para copiar al portapapeles:\n\n\(record.text)"
                    self.menu.addItem(item)
                }
            }

            self.menu.addItem(NSMenuItem.separator())

            // 3. Acciones esenciales
            let dictationFolderItem = NSMenuItem(title: "Abrir carpeta de dictados", action: #selector(self.openDictationFolder), keyEquivalent: "d")
            dictationFolderItem.target = self
            self.menu.addItem(dictationFolderItem)

            let launchAtLoginItem = NSMenuItem(title: "Iniciar al encender el Mac", action: #selector(self.toggleLaunchAtLogin), keyEquivalent: "")
            launchAtLoginItem.target = self
            launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            self.menu.addItem(launchAtLoginItem)

            // 4. Submenú Avanzado (recoge todo lo técnico en un submenú limpio)
            let advancedMenu = NSMenu(title: "Avanzado")

            let modelName = URL(fileURLWithPath: config.resolvedModelPath).lastPathComponent
            let modelExists = FileManager.default.fileExists(atPath: config.resolvedModelPath)
            let modelItem = NSMenuItem(title: "Modelo: \(modelName)\(modelExists ? " ✓" : " (Falta)")", action: nil, keyEquivalent: "")
            modelItem.isEnabled = false
            advancedMenu.addItem(modelItem)

            let apiKeySet = ConfigManager.shared.getAPIKey() != nil
            let llmStatus = apiKeySet ? "Limpieza IA: \(config.llmModel) ✓" : "Limpieza IA: Desactivada"
            let llmItem = NSMenuItem(title: llmStatus, action: nil, keyEquivalent: "")
            llmItem.isEnabled = false
            advancedMenu.addItem(llmItem)

            let hotkeyInfo = "Atajos: ⌥ [\(config.standardHotkey)]  •  ⌘ [\(config.cleanupHotkey)]"
            let hotkeyItem = NSMenuItem(title: hotkeyInfo, action: nil, keyEquivalent: "")
            hotkeyItem.isEnabled = false
            advancedMenu.addItem(hotkeyItem)

            advancedMenu.addItem(NSMenuItem.separator())

            let configFolderItem = NSMenuItem(title: "Abrir carpeta de configuración", action: #selector(self.openConfigFolder), keyEquivalent: "c")
            configFolderItem.target = self
            advancedMenu.addItem(configFolderItem)

            let logItem = NSMenuItem(title: "Ver registro de actividad (Log)", action: #selector(self.openLogFile), keyEquivalent: "l")
            logItem.target = self
            advancedMenu.addItem(logItem)

            let permissionsItem = NSMenuItem(title: "Comprobar permisos del sistema", action: #selector(self.checkPermissions), keyEquivalent: "p")
            permissionsItem.target = self
            advancedMenu.addItem(permissionsItem)

            let reloadItem = NSMenuItem(title: "Recargar configuración", action: #selector(self.reloadConfig), keyEquivalent: "r")
            reloadItem.target = self
            advancedMenu.addItem(reloadItem)

            let advancedItem = NSMenuItem(title: "Avanzado", action: nil, keyEquivalent: "")
            advancedItem.submenu = advancedMenu
            self.menu.addItem(advancedItem)

            self.menu.addItem(NSMenuItem.separator())

            // 5. Salir
            let quitItem = NSMenuItem(title: "Salir de Typeless", action: #selector(self.quitApp), keyEquivalent: "q")
            quitItem.target = self
            self.menu.addItem(quitItem)
        }
    }

    @objc private func copyTranscriptItemClicked(_ sender: NSMenuItem) {
        if let record = sender.representedObject as? TranscriptRecord {
            HistoryLogger.shared.copyRecordToClipboard(record)
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
            alert.messageText = "Permisos de Typeless"
            alert.informativeText = "✓ Permisos de Accesibilidad concedidos.\n✓ Grabación y pegado activo.\n✓ Micrófono listo."
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

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                LogManager.shared.log("Launch at Login disabled.")
            } else {
                try SMAppService.mainApp.register()
                LogManager.shared.log("Launch at Login enabled.")
            }
        } catch {
            LogManager.shared.log("Failed to toggle Launch at Login: \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
