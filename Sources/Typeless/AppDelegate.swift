import Cocoa

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent app from closing when menu closes
        NSApplication.shared.setActivationPolicy(.accessory)

        LogManager.shared.log("=== Typeless started ===")

        // 1. Initialize Status Bar
        StatusItemManager.shared.setup()

        // 2. Request / Check Accessibility
        let isTrusted = KeyMonitor.isAccessibilityTrusted(prompt: true)
        LogManager.shared.log("Initial Accessibility check: \(isTrusted)")

        // 3. Setup Hotkey Listeners
        KeyMonitor.shared.onRecordingStart = { [weak self] mode in
            self?.handleRecordingStart(mode: mode)
        }

        KeyMonitor.shared.onRecordingStop = { [weak self] mode in
            self?.handleRecordingStop(mode: mode)
        }

        KeyMonitor.shared.onPermissionChanged = { trusted in
            LogManager.shared.log("Permission state changed: trusted = \(trusted)")
            StatusItemManager.shared.updateStatus(trusted ? .idle : .needsAccessibility)
            StatusItemManager.shared.rebuildMenu()
        }

        KeyMonitor.shared.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        LogManager.shared.log("=== Typeless terminating ===")
        KeyMonitor.shared.stop()
        recorder.cancel()
    }

    private func handleRecordingStart(mode: DictationMode) {
        let config = ConfigManager.shared.config
        let isClean = (mode == .cleanup)

        LogManager.shared.log("handleRecordingStart (cleanup: \(isClean))")
        StatusItemManager.shared.updateStatus(.recording(isCleaned: isClean))

        do {
            try recorder.startRecording(config: config)
        } catch {
            LogManager.shared.log("Failed to start recording: \(error.localizedDescription)")
            StatusItemManager.shared.updateStatus(.error(error.localizedDescription))
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
                StatusItemManager.shared.updateStatus(trusted ? .idle : .needsAccessibility)
            }
        }
    }

    private func handleRecordingStop(mode: DictationMode) {
        let config = ConfigManager.shared.config
        LogManager.shared.log("handleRecordingStop (mode: \(mode))")

        do {
            let wavURL = try recorder.stopRecording(config: config)
            LogManager.shared.log("Recording stopped, audio saved to: \(wavURL.path)")
            StatusItemManager.shared.updateStatus(.transcribing)

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                await self.processAudio(wavURL: wavURL, mode: mode, config: config)
            }
        } catch AudioRecorderError.recordingTooShort(let dur) {
            LogManager.shared.log("Recording ignored (too short: \(String(format: "%.2f", dur))s)")
            let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
            StatusItemManager.shared.updateStatus(trusted ? .idle : .needsAccessibility)
        } catch {
            LogManager.shared.log("Failed to stop recording: \(error.localizedDescription)")
            StatusItemManager.shared.updateStatus(.error(error.localizedDescription))
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
                StatusItemManager.shared.updateStatus(trusted ? .idle : .needsAccessibility)
            }
        }
    }

    private func processAudio(wavURL: URL, mode: DictationMode, config: AppConfig) async {
        do {
            LogManager.shared.log("Beginning local transcription with whisper.cpp...")
            let rawTranscript = try transcriber.transcribe(audioURL: wavURL, config: config)
            LogManager.shared.log("Whisper raw transcript: \"\(rawTranscript)\"")

            var finalText = rawTranscript
            let isCleanedMode = (mode == .cleanup)

            if isCleanedMode {
                await MainActor.run {
                    StatusItemManager.shared.updateStatus(.cleaning)
                }
                LogManager.shared.log("Sending transcript to LLM for cleanup...")
                finalText = await LLMClient.shared.cleanupTranscript(rawTranscript, config: config)
                LogManager.shared.log("LLM cleaned transcript: \"\(finalText)\"")
            }

            let textToPaste = finalText
            let pasteDelay = config.pasteDelayMs

            await MainActor.run {
                LogManager.shared.log("Pasting transcript via PasteManager...")
                PasteManager.shared.pasteAndRestore(text: textToPaste, delayMs: pasteDelay)
            }

            HistoryLogger.shared.log(text: textToPaste, isCleaned: isCleanedMode, config: config)
            LogManager.shared.log("History logged successfully.")

            await MainActor.run {
                let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
                StatusItemManager.shared.updateStatus(trusted ? .idle : .needsAccessibility)
            }
        } catch TranscriberError.emptyTranscription {
            LogManager.shared.log("Transcription resulted in no speech recognized.")
            await MainActor.run {
                let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
                StatusItemManager.shared.updateStatus(trusted ? .idle : .needsAccessibility)
            }
        } catch {
            LogManager.shared.log("Transcription error: \(error.localizedDescription)")
            await MainActor.run {
                StatusItemManager.shared.updateStatus(.error(error.localizedDescription))
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                let trusted = KeyMonitor.isAccessibilityTrusted(prompt: false)
                StatusItemManager.shared.updateStatus(trusted ? .idle : .needsAccessibility)
            }
        }
    }
}
