import Foundation

enum PromptBuilder {
    /// Shared suffix appended to all system prompts to prevent the model from
    /// wasting tokens on internal reasoning (`<think>` blocks).
    private static let noThinkSuffix = " Do not include any <think> tags or internal reasoning. Respond immediately and directly."

    // MARK: - Fun Mode

    static func funSystemPrompt(personality: Personality) -> String {
        personality.systemPrompt + noThinkSuffix
    }

    static func funUserPrompt(topic: String) -> String {
        topic + " /no_think"
    }

    // MARK: - Schedule Mode

    static func scheduleSystemPrompt() -> String {
        """
        Brief someone on their day in 3-5 sentences. \
        Be concise and conversational. No lists or markdown.\
        \(noThinkSuffix)
        """
    }

    static func scheduleUserPrompt(events: [String], reminders: [String]) -> String {
        var parts: [String] = []

        if !events.isEmpty {
            parts.append("Events:\n" + events.joined(separator: "\n"))
        }

        if !reminders.isEmpty {
            parts.append("Reminders:\n" + reminders.joined(separator: "\n"))
        }

        if parts.isEmpty {
            return "Nothing on my schedule today. Comment on that. /no_think"
        }

        return parts.joined(separator: "\n") + "\n\nBrief me. /no_think"
    }

    // MARK: - Screen Time Mode

    static func screenTimeSystemPrompt() -> String {
        """
        Roast someone's phone usage in 4-6 sentences. Be funny and mean. \
        No lists or markdown.\
        \(noThinkSuffix)
        """
    }

    static func screenTimeUserPrompt(data: [String]) -> String {
        if data.isEmpty {
            return "Roast me for hiding my screen time. /no_think"
        }

        // Only top 3 apps, comma-separated — keeps prompt short for 0.6B model
        let top3 = data.prefix(3).joined(separator: ", ")
        return "I used \(top3). Roast me. /no_think"
    }

    // MARK: - TTS Text Normalization

    /// Expand abbreviations and symbols the TTS engine won't pronounce correctly.
    static func normalizeForTTS(_ text: String) -> String {
        var result = text

        // Duration shorthands: "2h 15m", "7h", "45m", "1h30m"
        result = result.replacingOccurrences(
            of: #"(\d+)\s*h\s*(\d+)\s*m\b"#,
            with: "$1 hours $2 minutes",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(\d+)\s*h\b"#,
            with: "$1 hours",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(\d+)\s*m\b"#,
            with: "$1 minutes",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(\d+)\s*s\b"#,
            with: "$1 seconds",
            options: .regularExpression
        )

        // Time: "2:30 PM" → "2 30 PM"
        result = result.replacingOccurrences(
            of: #"(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)"#,
            with: "$1 $2 $3",
            options: .regularExpression
        )

        // Common symbols
        result = result.replacingOccurrences(of: "&", with: " and ")
        result = result.replacingOccurrences(of: "%", with: " percent")
        result = result.replacingOccurrences(of: " w/ ", with: " with ")
        result = result.replacingOccurrences(of: " w/o ", with: " without ")

        // Collapse multiple spaces
        result = result.replacingOccurrences(
            of: #" {2,}"#,
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespaces)
    }
}
