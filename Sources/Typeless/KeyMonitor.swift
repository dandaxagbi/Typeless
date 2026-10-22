import Cocoa
import Carbon

public enum DictationMode {
    case standard
    case cleanup
}

public final class KeyMonitor {
    public static let shared = KeyMonitor()

    public var onRecordingStart: ((DictationMode) -> Void)?
    public var onRecordingStop: ((DictationMode) -> Void)?
    public var onPermissionChanged: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalNSEventMonitor: Any?
    private var permissionTimer: Timer?

    public private(set) var isHoldingStandard: Bool = false
    public private(set) var isHoldingCleanup: Bool = false

    // Device-dependent modifier flags (IOKit / Carbon)
    private static let NX_DEVICERALTMASK: UInt64  = 0x00000040 // Right Option
    private static let NX_DEVICELALTMASK: UInt64  = 0x00000020 // Left Option
    private static let NX_DEVICERCMDMASK: UInt64  = 0x00000010 // Right Command
    private static let NX_DEVICELCMDMASK: UInt64  = 0x00000008 // Left Command
    private static let NX_DEVICERSHIFTMASK: UInt64 = 0x00000004 // Right Shift
    private static let NX_DEVICELSHIFTMASK: UInt64 = 0x00000002 // Left Shift
    private static let NX_DEVICERCTLKEYMASK: UInt64 = 0x00002000 // Right Control

    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private init() {}

    public func start() {
        stop()

        let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
        LogManager.shared.log("KeyMonitor start() — Accessibility trusted: \(trusted)")

        // 1. Attempt to create low-level CGEventTap
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let observer = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        )

        if let tap = tap {
            self.eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            LogManager.shared.log("CGEventTap created successfully and enabled.")
        } else {
            LogManager.shared.log("CGEventTap creation returned nil (Accessibility permission likely not granted yet).")
        }

        // 2. Also register NSEvent global monitor as backup
        self.globalNSEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] nsEvent in
            guard let self = self else { return }
            self.processFlags(
                rawFlags: UInt64(nsEvent.modifierFlags.rawValue),
                keyCode: Int64(nsEvent.keyCode),
                source: "NSEventMonitor"
            )
        }

        // 3. Start auto-reconnect timer if permission was missing
        startPermissionWatcher()
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        if let monitor = globalNSEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalNSEventMonitor = nil
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func startPermissionWatcher() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
            if self.eventTap == nil && trusted {
                LogManager.shared.log("Accessibility permission granted! Reinitializing KeyMonitor...")
                self.start()
                self.onPermissionChanged?(true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.permissionTimer = timer
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let nsEvent = NSEvent(cgEvent: event)
            let rawFlags = nsEvent.map { UInt64($0.modifierFlags.rawValue) } ?? event.flags.rawValue
            processFlags(rawFlags: rawFlags, keyCode: keyCode, source: "CGEventTap")
        }

        return Unmanaged.passUnretained(event)
    }

    private func getMask(for name: String) -> (mask: UInt64, defaultKeycode: Int64, flagBit: UInt64) {
        switch name.lowercased() {
        case "rightoption", "rightalt":
            return (KeyMonitor.NX_DEVICERALTMASK, 61, UInt64(NSEvent.ModifierFlags.option.rawValue))
        case "rightcommand", "rightcmd":
            return (KeyMonitor.NX_DEVICERCMDMASK, 54, UInt64(NSEvent.ModifierFlags.command.rawValue))
        case "rightshift":
            return (KeyMonitor.NX_DEVICERSHIFTMASK, 60, UInt64(NSEvent.ModifierFlags.shift.rawValue))
        case "rightcontrol", "rightctrl":
            return (KeyMonitor.NX_DEVICERCTLKEYMASK, 62, UInt64(NSEvent.ModifierFlags.control.rawValue))
        case "leftoption", "leftalt":
            return (KeyMonitor.NX_DEVICELALTMASK, 58, UInt64(NSEvent.ModifierFlags.option.rawValue))
        default:
            return (KeyMonitor.NX_DEVICERALTMASK, 61, UInt64(NSEvent.ModifierFlags.option.rawValue))
        }
    }

    private func processFlags(rawFlags: UInt64, keyCode: Int64, source: String) {
        let config = ConfigManager.shared.config
        let standard = getMask(for: config.standardHotkey)
        let cleanup = getMask(for: config.cleanupHotkey)

        // Check if standard key (e.g. Right Option) is active
        let standardDeviceBit = (rawFlags & standard.mask) != 0
        let standardKeyActive = (keyCode == standard.defaultKeycode) && ((rawFlags & standard.flagBit) != 0)
        let isStandardPressed = standardDeviceBit || standardKeyActive

        // Check if cleanup key (e.g. Right Command) is active
        let cleanupDeviceBit = (rawFlags & cleanup.mask) != 0
        let cleanupKeyActive = (keyCode == cleanup.defaultKeycode) && ((rawFlags & cleanup.flagBit) != 0)
        let isCleanupPressed = cleanupDeviceBit || cleanupKeyActive

        // Also check if general modifier is completely released
        let optionKeyReleased = ((rawFlags & standard.flagBit) == 0) && (keyCode == standard.defaultKeycode || standardDeviceBit == false)
        let commandKeyReleased = ((rawFlags & cleanup.flagBit) == 0) && (keyCode == cleanup.defaultKeycode || cleanupDeviceBit == false)

        // Standard Push-To-Talk
        if isStandardPressed && !isHoldingStandard && !isHoldingCleanup {
            isHoldingStandard = true
            LogManager.shared.log("[\(source)] Standard hotkey pressed (keyCode: \(keyCode), rawFlags: 0x\(String(rawFlags, radix: 16))) -> Recording start")
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStart?(.standard)
            }
        } else if isHoldingStandard && (!isStandardPressed || optionKeyReleased) {
            isHoldingStandard = false
            LogManager.shared.log("[\(source)] Standard hotkey released -> Recording stop")
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStop?(.standard)
            }
        }

        // Cleanup Push-To-Talk
        if isCleanupPressed && !isHoldingCleanup && !isHoldingStandard {
            isHoldingCleanup = true
            LogManager.shared.log("[\(source)] Cleanup hotkey pressed (keyCode: \(keyCode), rawFlags: 0x\(String(rawFlags, radix: 16))) -> Cleanup recording start")
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStart?(.cleanup)
            }
        } else if isHoldingCleanup && (!isCleanupPressed || commandKeyReleased) {
            isHoldingCleanup = false
            LogManager.shared.log("[\(source)] Cleanup hotkey released -> Cleanup recording stop")
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStop?(.cleanup)
            }
        }
    }
}
