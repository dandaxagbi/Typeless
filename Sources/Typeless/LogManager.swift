import Foundation

public final class LogManager {
    public static let shared = LogManager()

    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.typeless.logmanager")
    private let dateFormatter: DateFormatter

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/typeless", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.logFileURL = dir.appendingPathComponent("typeless.log")

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    public func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)\n"

        // Also print to stdout/console
        print(formatted, terminator: "")

        queue.async {
            guard let data = formatted.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: self.logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                FileManager.default.createFile(atPath: self.logFileURL.path, contents: data, attributes: [.posixPermissions: 0o600])
            }
        }
    }

    public var logPath: String {
        return logFileURL.path
    }
}
