import Foundation
import AppKit

public struct TranscriptRecord: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let text: String
    public let isCleaned: Bool

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    public var summary: String {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if clean.count <= 42 {
            return clean
        }
        let index = clean.index(clean.startIndex, offsetBy: 40)
        return String(clean[..<index]) + "..."
    }
}

public final class HistoryLogger {
    public static let shared = HistoryLogger()

    private(set) var recentRecords: [TranscriptRecord] = []
    private let queue = DispatchQueue(label: "com.typeless.historylogger")

    public var onHistoryUpdated: (([TranscriptRecord]) -> Void)?

    private init() {}

    public func log(text: String, isCleaned: Bool, config: AppConfig) {
        let record = TranscriptRecord(timestamp: Date(), text: text, isCleaned: isCleaned)

        queue.async {
            // 1. Maintain last 10 in memory
            self.recentRecords.insert(record, at: 0)
            if self.recentRecords.count > 10 {
                self.recentRecords.removeLast()
            }

            // 2. Append to ~/Dictation/YYYY-MM.md
            self.appendToFile(record: record, folderPath: config.resolvedDictationFolder)

            // 3. Notify listeners
            DispatchQueue.main.async {
                self.onHistoryUpdated?(self.recentRecords)
            }
        }
    }

    private func appendToFile(record: TranscriptRecord, folderPath: String) {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: folderPath)

        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let monthString = monthFormatter.string(from: record.timestamp)

        let fileURL = folderURL.appendingPathComponent("\(monthString).md")

        let fullDateFormatter = DateFormatter()
        fullDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestampStr = fullDateFormatter.string(from: record.timestamp)

        let modeTag = record.isCleaned ? " [Cleaned]" : ""
        let markdownEntry = "\n### \(timestampStr)\(modeTag)\n\n\(record.text)\n\n---\n"

        if let data = markdownEntry.data(using: .utf8) {
            if fileManager.fileExists(atPath: fileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                let header = "# Dictation History - \(monthString)\n"
                let initialContent = header + markdownEntry
                try? initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    public func copyRecordToClipboard(_ record: TranscriptRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.text, forType: .string)
    }
}
