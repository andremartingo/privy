import AVFoundation
import Foundation
import FluidAudio
import SwiftData
import SwiftUI

@Model
class Memo {
    typealias StartTime = CMTime

    var title: String
    var text: AttributedString
    var url: URL?  // Audio file URL
    var sourceURL: URL?
    var recordingURL: URL?
    var isDone: Bool
    var createdAt: Date
    var duration: TimeInterval?
    var transcriptText: String = ""
    var cleanedTranscriptText: String?
    var languageCode: String?
    var detectedLanguageCode: String?
    var modelId: String = TranscriptionOptions.default.modelId
    var transcriptionStatus: TranscriptionStatus = TranscriptionStatus.pending
    var transcriptionProgress: Double = 0
    var errorMessage: String?
    var transcriptSegments: [TranscriptSegment] = []

    // AI-enhanced content - now using AttributedString for rich formatting
    var summary: AttributedString?

    // Speaker diarization data
    var hasSpeakerData: Bool = false
    var speakerSegments: [SpeakerSegment] = []

    // This can't be persisted with SwiftData since DiarizationResult isn't a @Model
    @Transient var diarizationResult: DiarizationResult?

    init(
        title: String, text: AttributedString, url: URL? = nil, isDone: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.title = title
        self.text = text
        self.url = url
        self.sourceURL = url
        self.recordingURL = url
        self.isDone = isDone
        self.duration = duration
        self.transcriptText = String(text.characters)
        self.cleanedTranscriptText = nil
        self.languageCode = TranscriptionOptions.default.languageCode
        self.detectedLanguageCode = nil
        self.modelId = TranscriptionOptions.default.modelId
        self.transcriptionStatus = isDone ? .completed : .pending
        self.transcriptionProgress = isDone ? 1 : 0
        self.errorMessage = nil
        self.transcriptSegments = []
        self.createdAt = Date()
        self.summary = nil
        self.hasSpeakerData = false
        self.speakerSegments = []
        self.diarizationResult = nil
    }
}

extension Memo {
    static func blank() -> Memo {
        return .init(title: "New Memo", text: AttributedString(""))
    }

    static func imported(_ importedAudio: ImportedAudio) -> Memo {
        let memo = Memo(
            title: importedAudio.title,
            text: AttributedString(""),
            url: importedAudio.localURL,
            isDone: false,
            duration: importedAudio.duration
        )
        memo.sourceURL = importedAudio.originalURL
        memo.recordingURL = importedAudio.localURL
        memo.transcriptionStatus = .pending
        memo.transcriptionProgress = 0
        return memo
    }

    func updateTranscript(_ transcript: String, modelId: String, languageCode: String?) {
        transcriptText = transcript
        text = AttributedString(transcript)
        self.modelId = modelId
        self.languageCode = languageCode
        transcriptionStatus = .completed
        transcriptionProgress = 1
        errorMessage = nil
        isDone = true
    }

    func replaceTranscriptSegments(_ segments: [TranscriptSegment], in context: ModelContext) {
        for existingSegment in transcriptSegments {
            context.delete(existingSegment)
        }
        transcriptSegments.removeAll()

        for segment in segments {
            segment.memo = self
            transcriptSegments.append(segment)
            context.insert(segment)
        }
    }

    // MARK: - Speaker Diarization Methods

        /// Updates the memo with diarization results
    func updateWithDiarizationResult(_ result: DiarizationResult, in context: ModelContext) {
        self.diarizationResult = result
        self.hasSpeakerData = !result.segments.isEmpty

        // Clear existing segments
        self.speakerSegments.removeAll()

        // Create speaker segments and ensure speakers exist in database
        for segment in result.segments {
            let speakerSegment = SpeakerSegment(
                speakerId: segment.speakerId,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore,
                embedding: segment.embedding
            )
            speakerSegment.memo = self
            self.speakerSegments.append(speakerSegment)
            context.insert(speakerSegment)

            // Ensure speaker exists in database
            let speaker = Speaker.findOrCreate(withId: segment.speakerId, in: context)
            speaker.embedding = segment.embedding
        }
    }

    /// Returns an attributed string with speaker information embedded
    func textWithSpeakerAttributes(context: ModelContext) -> AttributedString {
        guard hasSpeakerData else { return text }

        var attributedText = AttributedString(String(text.characters))

                // Apply speaker attributes to segments
        for segment in speakerSegments.sorted(by: { $0.startTime < $1.startTime }) {
            // Find the corresponding speaker
            let speakerId = segment.speakerId
            let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { speaker in
                speaker.id == speakerId
            })
            if let speaker = try? context.fetch(descriptor).first {

                // Estimate character positions based on timing (rough approximation)
                let totalDuration = duration ?? 1.0
                let totalLength = attributedText.characters.count

                let startPosition = max(0, Int((segment.startTime / totalDuration) * Double(totalLength)))
                let endPosition = min(totalLength, Int((segment.endTime / totalDuration) * Double(totalLength)))

                if startPosition < endPosition {
                    let range = attributedText.characters.index(attributedText.startIndex, offsetBy: startPosition)..<attributedText.characters.index(attributedText.startIndex, offsetBy: endPosition)

                    attributedText[range].foregroundColor = speaker.displayColor
                    attributedText[range][AttributedString.speakerIDKey] = speaker.id
                    attributedText[range][AttributedString.speakerConfidenceKey] = segment.confidence
                }
            }
        }

        return attributedText
    }

        /// Returns speakers present in this memo
    func speakers(in context: ModelContext) -> [Speaker] {
        guard hasSpeakerData else { return [] }

        let speakerIds = Set(speakerSegments.map { $0.speakerId })
        let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { speaker in
            speakerIds.contains(speaker.id)
        })

        return (try? context.fetch(descriptor)) ?? []
    }

    /// Returns a formatted transcript with speaker labels
    func formattedTranscriptWithSpeakers(context: ModelContext) -> AttributedString {
        guard hasSpeakerData else { return textBrokenUpByParagraphs() }

        var result = AttributedString("")
        let sortedSegments = speakerSegments.sorted(by: { $0.startTime < $1.startTime })

                for (index, segment) in sortedSegments.enumerated() {
            // Get speaker information
            let speakerId = segment.speakerId
            let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { speaker in
                speaker.id == speakerId
            })
            let speaker = try? context.fetch(descriptor).first
            let speakerName = speaker?.name ?? "Speaker \(segment.speakerId)"

            // Add speaker label
            var speakerLabel = AttributedString("\(speakerName): ")
            speakerLabel.font = .headline
            speakerLabel.foregroundColor = speaker?.displayColor ?? .primary

            result.append(speakerLabel)

            // Add segment text
            var segmentText = AttributedString(segment.text)
            segmentText.foregroundColor = .primary
            result.append(segmentText)

            // Add line break between segments
            if index < sortedSegments.count - 1 {
                result.append(AttributedString("\n\n"))
            }
        }

        return result
    }

    func textBrokenUpByParagraphs() -> AttributedString {
        print(String(text.characters))
        if url == nil {
            print("url was nil")
            return text
        } else {
            var final = AttributedString("")
            var working = AttributedString("")
            let copy = text
            copy.runs.forEach { run in
                if copy[run.range].characters.contains(".") {
                    working.append(copy[run.range])
                    final.append(working)
                    final.append(AttributedString("\n\n"))
                    working = AttributedString("")
                } else {
                    if working.characters.isEmpty {
                        let newText = copy[run.range].characters
                        let attributes = run.attributes
                        let trimmed = newText.trimmingPrefix(" ")
                        let newAttributed = AttributedString(trimmed, attributes: attributes)
                        working.append(newAttributed)
                    } else {
                        working.append(copy[run.range])
                    }
                }
            }

            if final.characters.isEmpty {
                return working
            }

            return final
        }
    }
}
