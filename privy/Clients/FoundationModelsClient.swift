import Dependencies
import Foundation
import FoundationModels

struct FoundationModelEnhancements: Equatable, Sendable {
    var summary: AttributedString
    var title: String
}

struct FoundationModelsClient: Sendable {
    var isAvailable: @MainActor @Sendable () -> Bool
    var generateEnhancements: @MainActor @Sendable (String) async throws -> FoundationModelEnhancements
    var generateSummary: @MainActor @Sendable (String) async throws -> AttributedString
    var generateTitle: @MainActor @Sendable (String) async throws -> String
}

extension FoundationModelsClient {
    static var live: Self {
        Self(
            isAvailable: {
                FoundationModelsService.shared.isAvailable()
            },
            generateEnhancements: { transcript in
                try await FoundationModelsService.shared.generateEnhancements(from: transcript)
            },
            generateSummary: { transcript in
                try await FoundationModelsService.shared.generateSummary(from: transcript)
            },
            generateTitle: { text in
                try await FoundationModelsService.shared.generateTitle(from: text)
            }
        )
    }

    static var preview: Self {
        Self(
            isAvailable: { true },
            generateEnhancements: { _ in
                FoundationModelEnhancements(
                    summary: AttributedString("Preview summary"),
                    title: "Preview Memo"
                )
            },
            generateSummary: { _ in AttributedString("Preview summary") },
            generateTitle: { _ in "Preview Memo" }
        )
    }
}

extension FoundationModelsClient: DependencyKey {
    static var liveValue: Self {
        #if DEBUG
            preview
        #else
            live
        #endif
    }
    static let previewValue = preview
}

extension DependencyValues {
    var foundationModelsClient: FoundationModelsClient {
        get { self[FoundationModelsClient.self] }
        set { self[FoundationModelsClient.self] = newValue }
    }
}

enum FoundationModelsError: LocalizedError {
    case contextWindowExceeded
    case unsupportedLanguage
    case generationFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .contextWindowExceeded:
            return "The conversation has become too long. Please start a new session."
        case .unsupportedLanguage:
            return "The current language or locale is not supported by Foundation Models."
        case let .generationFailed(error):
            return "Failed to generate content: \(error.localizedDescription)"
        }
    }
}

@MainActor
private final class FoundationModelsService {
    static let shared = FoundationModelsService()

    private let maxSinglePassSummaryCharacters = 7_000
    private let maxChunkCharacters = 6_000

    private init() {}

    func isAvailable() -> Bool {
        SystemLanguageModel.default.isAvailable
    }

    func generateEnhancements(from transcript: String) async throws -> FoundationModelEnhancements {
        guard SystemLanguageModel.default.isAvailable else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "Foundation Models not available", code: -1)
            )
        }

        let transcriptText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcriptText.isEmpty else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "No content to enhance", code: -2)
            )
        }

        do {
            let summary = try await generateSummary(from: transcriptText)
            let title = try? await generateTitle(from: String(summary.characters))
            return FoundationModelEnhancements(summary: summary, title: title ?? "New Note")
        } catch {
            CoreLogger.info("summaryGenerationFailed: \(error.localizedDescription)")
            let fallbackTitleInput = String(transcriptText.prefix(maxSinglePassSummaryCharacters))
            let title = try? await generateTitle(from: fallbackTitleInput)
            return FoundationModelEnhancements(
                summary: AttributedString("Something went wrong generating a summary."),
                title: title ?? "New Note"
            )
        }
    }

    func generateSummary(from text: String) async throws -> AttributedString {
        if text.count <= maxSinglePassSummaryCharacters {
            return try await generateRichSummary(from: text)
        }

        return try await generateChunkedSummary(from: text)
    }

    func generateTitle(from text: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
                You are an expert at creating clear, descriptive titles for voice memos and transcripts.
                Your task is to create a concise, informative title that captures the main topic or purpose.

                Guidelines:
                - Keep titles between 3-8 words
                - Use title case (capitalize major words)
                - Focus on the main topic or key insight
                - Avoid generic words like memo or recording
                - Be specific and descriptive
                - Do not wrap the title in quotes
                """
        )

        let prompt = """
            Create a clear, descriptive title for this voice memo transcript.
            Do not include quotes in your response.

            \(text)
            """

        let title = try await generateText(
            session: session,
            prompt: prompt,
            options: temperatureOptions(0.3)
        )
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
    }

    private func generateRichSummary(from text: String) async throws -> AttributedString {
        let session = LanguageModelSession(
            instructions: """
                You are an expert at creating concise, informative summaries of voice memos and transcripts.
                Your summaries should capture the key points, main topics, and important details.

                Guidelines:
                - Create 2-4 well-structured paragraphs
                - Include key points and important details
                - Mark important concepts or key terms that should be highlighted
                - Output in markdown format
                """
        )

        let prompt = "Create a comprehensive summary of this voice memo transcript:\n\n\(text)"
        let summaryText = try await generateText(
            session: session,
            prompt: prompt,
            options: temperatureOptions(0.4)
        )

        return try AttributedString(markdown: summaryText)
    }

    private func generateChunkedSummary(from text: String) async throws -> AttributedString {
        let chunks = chunkTranscript(text, maxCharacters: maxChunkCharacters)
        guard !chunks.isEmpty else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "No content to enhance", code: -2)
            )
        }

        var sectionSummaries: [String] = []
        sectionSummaries.reserveCapacity(chunks.count)

        for (index, chunk) in chunks.enumerated() {
            let summary = try await generateSectionSummary(
                from: chunk,
                index: index + 1,
                total: chunks.count
            )
            sectionSummaries.append(summary)
        }

        let finalSummaryText = try await reduceSectionSummaries(sectionSummaries)
        return try AttributedString(markdown: finalSummaryText)
    }

    private func generateSectionSummary(from text: String, index: Int, total: Int) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
                You extract concise notes from one excerpt of a longer transcript.
                Preserve concrete facts, decisions, action items, names, dates, numbers, and unresolved questions.
                Do not invent context from outside this excerpt.
                Do not mention sections, chunks, excerpts, or part numbers.
                Output concise markdown bullets with no heading.
                """
        )

        let prompt = """
            Extract the important notes from transcript excerpt \(index) of \(total).
            These notes are internal and will be merged into one final overall summary.
            Do not include section labels or excerpt labels.

            Transcript excerpt:
            \(text)
            """

        return try await generateText(
            session: session,
            prompt: prompt,
            options: temperatureOptions(0.3)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reduceSectionSummaries(_ summaries: [String]) async throws -> String {
        let joinedSummaries = summaries.joined(separator: "\n\n")

        if joinedSummaries.count <= maxSinglePassSummaryCharacters {
            return try await generateFinalSummary(from: joinedSummaries)
        }

        let summaryChunks = chunkTranscript(
            joinedSummaries,
            maxCharacters: maxSinglePassSummaryCharacters
        )
        var reducedSummaries: [String] = []
        reducedSummaries.reserveCapacity(summaryChunks.count)

        for (index, chunk) in summaryChunks.enumerated() {
            let reduced = try await generateSectionSummary(
                from: chunk,
                index: index + 1,
                total: summaryChunks.count
            )
            reducedSummaries.append(reduced)
        }

        return try await reduceSectionSummaries(reducedSummaries)
    }

    private func generateFinalSummary(from sectionSummaries: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
                You create one cohesive final summary from internal notes extracted from a longer transcript.
                Produce a useful, concise markdown summary for the end user.
                Include key topics, decisions, action items, names, dates, numbers, and unresolved questions when present.
                Merge related points across the entire conversation.
                Do not organize the answer by section, chunk, excerpt, or part.
                Do not write labels like "Section 1", "Part 2", or "Excerpt".
                Prefer a brief overview followed by topic-based bullets only when useful.
                """
        )

        let prompt = """
            Create one general summary from these internal notes.
            The notes came from multiple chunks, but the final summary must read as one unified summary.

            \(sectionSummaries)
            """

        return try await generateText(
            session: session,
            prompt: prompt,
            options: temperatureOptions(0.35)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateText(
        session: LanguageModelSession,
        prompt: String,
        options: GenerationOptions? = nil
    ) async throws -> String {
        do {
            let response: LanguageModelSession.Response<String>
            if let options {
                response = try await session.respond(to: prompt, options: options)
            } else {
                response = try await session.respond(to: prompt)
            }
            return response.content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw FoundationModelsError.contextWindowExceeded
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
            throw FoundationModelsError.unsupportedLanguage
        } catch {
            throw FoundationModelsError.generationFailed(error)
        }
    }

    private func temperatureOptions(_ temperature: Double) -> GenerationOptions {
        GenerationOptions(temperature: temperature)
    }

    private func chunkTranscript(_ text: String, maxCharacters: Int) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }

        let paragraphs = trimmedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var currentChunk = ""

        for paragraph in paragraphs {
            if paragraph.count > maxCharacters {
                appendCurrentChunk(&currentChunk, to: &chunks)
                chunks.append(contentsOf: splitLongParagraph(paragraph, maxCharacters: maxCharacters))
            } else if currentChunk.isEmpty {
                currentChunk = paragraph
            } else if currentChunk.count + paragraph.count + 2 <= maxCharacters {
                currentChunk += "\n\n\(paragraph)"
            } else {
                appendCurrentChunk(&currentChunk, to: &chunks)
                currentChunk = paragraph
            }
        }

        appendCurrentChunk(&currentChunk, to: &chunks)
        return chunks
    }

    private func splitLongParagraph(_ paragraph: String, maxCharacters: Int) -> [String] {
        var chunks: [String] = []
        var remaining = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)

        while remaining.count > maxCharacters {
            let splitIndex = preferredSplitIndex(in: remaining, maxCharacters: maxCharacters)
            let chunk = String(remaining[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            remaining = String(remaining[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !remaining.isEmpty {
            chunks.append(remaining)
        }

        return chunks
    }

    private func preferredSplitIndex(in text: String, maxCharacters: Int) -> String.Index {
        let targetIndex = text.index(text.startIndex, offsetBy: maxCharacters)
        let searchRange = text.startIndex..<targetIndex

        if let sentenceIndex = text.range(
            of: ". ",
            options: .backwards,
            range: searchRange
        )?.upperBound {
            return sentenceIndex
        }

        if let spaceIndex = text.range(
            of: " ",
            options: .backwards,
            range: searchRange
        )?.upperBound {
            return spaceIndex
        }

        return targetIndex
    }

    private func appendCurrentChunk(_ currentChunk: inout String, to chunks: inout [String]) {
        let trimmedChunk = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedChunk.isEmpty {
            chunks.append(trimmedChunk)
        }
        currentChunk = ""
    }
}
