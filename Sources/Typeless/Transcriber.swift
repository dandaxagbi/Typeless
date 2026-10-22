import Foundation

public enum TranscriberError: LocalizedError {
    case whisperCliNotFound(String)
    case modelNotFound(String)
    case transcriptionFailed(String)
    case emptyTranscription

    public var errorDescription: String? {
        switch self {
        case .whisperCliNotFound(let path):
            return "whisper-cli executable not found at '\(path)'. Please install whisper.cpp via 'brew install whisper.cpp'."
        case .modelNotFound(let path):
            return "Whisper model file not found at '\(path)'. Run './scripts/download_model.sh' to download it."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .emptyTranscription:
            return "No audible speech recognized."
        }
    }
}

public final class Transcriber {
    public init() {}

    public func transcribe(audioURL: URL, config: AppConfig) throws -> String {
        // Guarantee audio file is deleted after transcription
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let whisperCli = config.whisperCliPath
        guard FileManager.default.isExecutableFile(atPath: whisperCli) else {
            throw TranscriberError.whisperCliNotFound(whisperCli)
        }

        let modelPath = config.resolvedModelPath
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriberError.modelNotFound(modelPath)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: whisperCli)
        proc.arguments = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-nt", // no timestamps
            "-np", // no prints
            "-l", config.language,
            "-t", String(config.threads)
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            throw TranscriberError.transcriptionFailed(error.localizedDescription)
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let rawOut = String(data: outData, encoding: .utf8) ?? ""

        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let rawErr = String(data: errData, encoding: .utf8) ?? ""

        if proc.terminationStatus != 0 && rawOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let errorMsg = rawErr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriberError.transcriptionFailed("Exit code \(proc.terminationStatus): \(errorMsg)")
        }

        let cleaned = cleanTranscription(rawOut)
        if cleaned.isEmpty {
            throw TranscriberError.emptyTranscription
        }

        return cleaned
    }

    private func cleanTranscription(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var filtered: [String] = []

        let timestampRegex = try? NSRegularExpression(pattern: #"\[\d{2}:\d{2}[:\.]\d{2,3}\s*-->\s*\d{2}:\d{2}[:\.]\d{2,3}\]"#)

        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Strip timestamp brackets if present
            if let regex = timestampRegex {
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                trimmed = regex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
            }

            // Skip whisper-cli internal status output
            if trimmed.hasPrefix("whisper_") || trimmed.hasPrefix("system_info:") || trimmed.hasPrefix("main:") || trimmed.hasPrefix("read_audio_data:") {
                continue
            }

            // Skip special whisper tokens
            let lower = trimmed.lowercased()
            if lower == "[blank_audio]" || lower == "[inaudible]" || lower == "[music]" || lower == "[applause]" || lower == "[laughter]" {
                continue
            }

            if !trimmed.isEmpty {
                filtered.append(trimmed)
            }
        }

        return filtered.joined(separator: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
