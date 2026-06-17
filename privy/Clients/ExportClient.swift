import Dependencies
import Foundation

struct ExportClient: Sendable {
    var export: @MainActor @Sendable (Memo, ExportFormat) async throws -> URL
}

extension ExportClient {
    static var live: Self {
        Self { memo, format in
            try ExportService.export(memo: memo, format: format)
        }
    }

    static var preview: Self {
        Self { memo, format in
            try ExportService.export(memo: memo, format: format)
        }
    }
}

extension ExportClient: DependencyKey {
    static let liveValue = ExportClient.live
    static let previewValue = ExportClient.preview
}

extension DependencyValues {
    var exportClient: ExportClient {
        get { self[ExportClient.self] }
        set { self[ExportClient.self] = newValue }
    }
}

enum ExportService {
    @MainActor
    static func export(memo: Memo, format: ExportFormat) throws -> URL {
        let directory = try exportDirectory()
        let baseName = sanitizedFileName(memo.title.isEmpty ? "Transcript" : memo.title)
        let destination = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(format.fileExtension)
        let content = content(for: memo, format: format)
        try content.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    @MainActor
    private static func content(for memo: Memo, format: ExportFormat) -> String {
        let segments = memo.transcriptSegments.sorted { $0.startTime < $1.startTime }
        let transcript = memo.transcriptText.isEmpty
            ? String(memo.text.characters)
            : memo.transcriptText

        switch format {
        case .plainText:
            return transcript

        case .timestampedText:
            guard !segments.isEmpty else { return transcript }
            return segments.map {
                "[\(timestamp($0.startTime))] \($0.text)"
            }
            .joined(separator: "\n")

        case .srt:
            guard !segments.isEmpty else { return fallbackSingleSubtitle(transcript, format: .srt) }
            return segments.enumerated().map { index, segment in
                """
                \(index + 1)
                \(srtTimestamp(segment.startTime)) --> \(srtTimestamp(segment.endTime))
                \(segment.text)
                """
            }
            .joined(separator: "\n\n")

        case .vtt:
            let body: String
            if segments.isEmpty {
                body = fallbackSingleSubtitle(transcript, format: .vtt)
            } else {
                body = segments.map { segment in
                    """
                    \(vttTimestamp(segment.startTime)) --> \(vttTimestamp(segment.endTime))
                    \(segment.text)
                    """
                }
                .joined(separator: "\n\n")
            }
            return "WEBVTT\n\n\(body)"

        case .json:
            let payload = TranscriptExportPayload(
                title: memo.title,
                createdAt: memo.createdAt,
                duration: memo.duration,
                modelId: memo.modelId,
                languageCode: memo.languageCode,
                detectedLanguageCode: memo.detectedLanguageCode,
                transcript: transcript,
                segments: segments.map {
                    TranscriptSegmentExportPayload(
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        text: $0.text,
                        modelId: $0.modelId,
                        languageCode: $0.languageCode,
                        confidence: $0.confidence,
                        speakerId: $0.speakerId
                    )
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(payload),
                let string = String(data: data, encoding: .utf8)
            else {
                return "{}"
            }
            return string

        case .csv:
            guard !segments.isEmpty else {
                return "start,end,speaker,text\n,,,\(csvEscape(transcript))\n"
            }
            let rows = segments.map {
                [
                    timestamp($0.startTime),
                    timestamp($0.endTime),
                    $0.speakerId ?? "",
                    $0.text,
                ].map(csvEscape).joined(separator: ",")
            }
            return "start,end,speaker,text\n" + rows.joined(separator: "\n")
        }
    }

    private static func exportDirectory() throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Privy Exports", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fallbackSingleSubtitle(_ text: String, format: ExportFormat) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }

        switch format {
        case .srt:
            return "1\n00:00:00,000 --> 00:00:05,000\n\(body)"
        case .vtt:
            return "00:00:00.000 --> 00:00:05.000\n\(body)"
        default:
            return body
        }
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Transcript" : cleaned
    }

    private static func timestamp(_ time: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((time * 1_000).rounded()))
        let milliseconds = totalMilliseconds % 1_000
        let totalSeconds = totalMilliseconds / 1_000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    private static func srtTimestamp(_ time: TimeInterval) -> String {
        timestamp(time).replacingOccurrences(of: ".", with: ",")
    }

    private static func vttTimestamp(_ time: TimeInterval) -> String {
        timestamp(time)
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct TranscriptExportPayload: Encodable {
    var title: String
    var createdAt: Date
    var duration: TimeInterval?
    var modelId: String
    var languageCode: String?
    var detectedLanguageCode: String?
    var transcript: String
    var segments: [TranscriptSegmentExportPayload]
}

private struct TranscriptSegmentExportPayload: Encodable {
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var modelId: String
    var languageCode: String?
    var confidence: Double?
    var speakerId: String?
}
