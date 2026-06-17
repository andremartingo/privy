import Foundation
import SwiftData

enum TranscriptionStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case recording
    case preparing
    case transcribing
    case completed
    case failed
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .recording:
            return "Recording"
        case .preparing:
            return "Preparing"
        case .transcribing:
            return "Transcribing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case plainText
    case timestampedText
    case srt
    case vtt
    case json
    case csv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plainText:
            return "TXT"
        case .timestampedText:
            return "Timestamped TXT"
        case .srt:
            return "SRT"
        case .vtt:
            return "WebVTT"
        case .json:
            return "JSON"
        case .csv:
            return "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .plainText, .timestampedText:
            return "txt"
        case .srt:
            return "srt"
        case .vtt:
            return "vtt"
        case .json:
            return "json"
        case .csv:
            return "csv"
        }
    }
}

enum SpeechEngine: String, Codable, CaseIterable, Identifiable {
    case parakeet
    case appleSpeech

    var id: String { rawValue }
}

struct SpeechModel: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var engine: SpeechEngine
    var supportedLanguageCodes: [String]
    var defaultLanguageCode: String?
    var approximateDiskSize: Int64
    var supportsLanguageDetection: Bool
    var supportsStreamingOutput: Bool
    var supportsTimestamps: Bool
    var supportsTranslation: Bool

    static let parakeetV3 = SpeechModel(
        id: "parakeet-tdt-0.6b-v3",
        displayName: "Parakeet TDT 0.6B v3",
        engine: .parakeet,
        supportedLanguageCodes: ["en"],
        defaultLanguageCode: "en",
        approximateDiskSize: 469_000_000,
        supportsLanguageDetection: false,
        supportsStreamingOutput: false,
        supportsTimestamps: false,
        supportsTranslation: false
    )

    static let appleSpeechEnglish = SpeechModel(
        id: "apple-speech-en",
        displayName: "Apple Speech English",
        engine: .appleSpeech,
        supportedLanguageCodes: ["en-US", "en-GB", "en-CA", "en-AU"],
        defaultLanguageCode: "en-US",
        approximateDiskSize: 0,
        supportsLanguageDetection: false,
        supportsStreamingOutput: true,
        supportsTimestamps: true,
        supportsTranslation: false
    )

    static let availableModels: [SpeechModel] = [
        .parakeetV3,
        .appleSpeechEnglish,
    ]
}

struct TranscriptionOptions: Codable, Equatable {
    var modelId: String
    var languageCode: String?
    var detectLanguage: Bool
    var translateToEnglish: Bool
    var prompt: String
    var timestampsEnabled: Bool
    var cleanupEnabled: Bool

    static let `default` = TranscriptionOptions(
        modelId: SpeechModel.parakeetV3.id,
        languageCode: "en",
        detectLanguage: false,
        translateToEnglish: false,
        prompt: "",
        timestampsEnabled: true,
        cleanupEnabled: false
    )
}

@Model
final class TranscriptSegment {
    var id: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var modelId: String
    var languageCode: String?
    var confidence: Double?
    var speakerId: String?
    var memo: Memo?

    var duration: TimeInterval {
        max(0, endTime - startTime)
    }

    init(
        id: String = UUID().uuidString,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        modelId: String,
        languageCode: String? = nil,
        confidence: Double? = nil,
        speakerId: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.modelId = modelId
        self.languageCode = languageCode
        self.confidence = confidence
        self.speakerId = speakerId
    }
}
