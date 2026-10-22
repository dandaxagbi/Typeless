import Foundation

public struct AppConfig: Codable {
    public var modelPath: String
    public var whisperCliPath: String
    public var ffmpegPath: String
    public var audioDevice: String
    public var language: String
    public var threads: Int
    public var standardHotkey: String
    public var cleanupHotkey: String
    public var dictationFolder: String
    public var pasteDelayMs: Int
    public var minRecordingDurationSeconds: Double
    public var llmProvider: String
    public var llmModel: String
    public var llmBaseURL: String

    public static let `default`: AppConfig = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        // Find whisper-cli path
        let defaultWhisperPaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "\(home)/.local/bin/whisper-cli"
        ]
        let whisperPath = defaultWhisperPaths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/whisper-cli"

        // Find ffmpeg path
        let defaultFfmpegPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        let ffmpegPath = defaultFfmpegPaths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/ffmpeg"

        // Default model path (small.en)
        let defaultModel = "\(home)/.config/typeless/models/ggml-small.en.bin"

        return AppConfig(
            modelPath: defaultModel,
            whisperCliPath: whisperPath,
            ffmpegPath: ffmpegPath,
            audioDevice: ":default",
            language: "en",
            threads: 4,
            standardHotkey: "rightOption",
            cleanupHotkey: "rightCommand",
            dictationFolder: "\(home)/Dictation",
            pasteDelayMs: 400,
            minRecordingDurationSeconds: 0.35,
            llmProvider: "openai",
            llmModel: "gpt-4o-mini",
            llmBaseURL: "https://api.openai.com/v1"
        )
    }()

    public var resolvedModelPath: String {
        return (modelPath as NSString).expandingTildeInPath
    }

    public var resolvedDictationFolder: String {
        return (dictationFolder as NSString).expandingTildeInPath
    }
}

public final class ConfigManager {
    public static let shared = ConfigManager()

    public private(set) var config: AppConfig = .default
    public private(set) var envVars: [String: String] = [:]

    public var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/typeless", isDirectory: true)
    }

    public var configFileURL: URL {
        return configDirectory.appendingPathComponent("config.json")
    }

    public var envFileURL: URL {
        return configDirectory.appendingPathComponent(".env")
    }

    private init() {
        loadAll()
    }

    public func reload() {
        loadAll()
    }

    private func loadAll() {
        ensureDirectoryExists()
        loadEnv()
        loadConfig()
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func loadEnv() {
        var merged: [String: String] = [:]

        // Check ~/.config/typeless/.env
        loadEnvFile(at: envFileURL, into: &merged)

        // Check local ./.env if running from dev directory
        let localEnv = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: localEnv.path) && localEnv.path != envFileURL.path {
            loadEnvFile(at: localEnv, into: &merged)
        }

        // Also inherit any environment variables already in ProcessInfo
        for (k, v) in ProcessInfo.processInfo.environment {
            merged[k] = v
        }

        self.envVars = merged
    }

    private func loadEnvFile(at url: URL, into dict: inout [String: String]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let cleaned = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst(7)) : trimmed
            let parts = cleaned.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                dict[key] = value
            }
        }
    }

    private func loadConfig() {
        var baseConfig = AppConfig.default

        if FileManager.default.fileExists(atPath: configFileURL.path),
           let data = try? Data(contentsOf: configFileURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            baseConfig = decoded
        } else {
            // Write out initial default config so the user can see and modify it
            saveConfig(baseConfig)
        }

        // Environment overrides
        if let modelEnv = envVars["WHISPER_MODEL_PATH"], !modelEnv.isEmpty {
            baseConfig.modelPath = modelEnv
        }
        if let llmModelEnv = envVars["LLM_MODEL"], !llmModelEnv.isEmpty {
            baseConfig.llmModel = llmModelEnv
        }
        if let llmBaseURLEnv = envVars["LLM_BASE_URL"], !llmBaseURLEnv.isEmpty {
            baseConfig.llmBaseURL = llmBaseURLEnv
        }

        self.config = baseConfig
    }

    public func saveConfig(_ newConfig: AppConfig) {
        ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(newConfig) {
            try? data.write(to: configFileURL)
        }
        self.config = newConfig
    }

    public func getAPIKey() -> String? {
        let keys = [
            "OPENAI_API_KEY",
            "OPENROUTER_API_KEY",
            "GROQ_API_KEY",
            "ANTHROPIC_API_KEY",
            "LLM_API_KEY"
        ]
        for key in keys {
            if let val = envVars[key], !val.trimmingCharacters(in: .whitespaces).isEmpty {
                return val.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
