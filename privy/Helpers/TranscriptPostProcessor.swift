import Foundation

enum TranscriptPostProcessor {
    static func process(_ transcript: String, settings: AppSettings) -> String {
        var text = transcript

        if settings.cleanupEnabled {
            text = normalizeWhitespace(text)
        }

        if settings.reduceRepetitions || settings.strongerRepetitionReduction {
            text = reduceRepeatedWords(text, aggressive: settings.strongerRepetitionReduction)
        }

        if settings.cleanupEnabled {
            text = removeFillerPhrases(text)
        }

        text = applyWordReplacements(text, replacements: settings.wordReplacements)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([,.!?;:])", with: "$1", options: .regularExpression)
    }

    private static func removeFillerPhrases(_ text: String) -> String {
        let fillers = [
            "\\bum\\b",
            "\\buh\\b",
            "\\ber\\b",
            "\\bah\\b",
            "\\blike\\b",
            "\\byou know\\b",
            "\\bi mean\\b",
        ]
        var result = text
        for filler in fillers {
            result = result.replacingOccurrences(
                of: "(?i)(^|\\s)\(filler)(?=\\s|[,.!?;:]|$)",
                with: " ",
                options: .regularExpression
            )
        }
        return normalizeWhitespace(result)
    }

    private static func reduceRepeatedWords(_ text: String, aggressive: Bool) -> String {
        let pattern = aggressive
            ? "\\b(\\w+)(\\s+\\1\\b)+"
            : "\\b(\\w+)(\\s+\\1\\b)"
        return text.replacingOccurrences(
            of: pattern,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func applyWordReplacements(_ text: String, replacements: String) -> String {
        var result = text
        let lines = replacements
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        for line in lines {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let original = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else { continue }
            result = result.replacingOccurrences(of: original, with: replacement)
        }

        return result
    }
}
