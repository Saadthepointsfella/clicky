//
//  ClicksLearningExtractor.swift
//  leanring-buddy
//
//  Isolated Claude-powered extraction service for Clicks learning memory.
//

import Foundation

struct ClicksCompletedExchange {
    let userTranscript: String
    let assistantResponse: String
    let sourceApp: String
    let createdAt: Date
}

struct ClicksLearningExtractor {
    private let claudeAPI: ClaudeAPI

    init(claudeAPI: ClaudeAPI) {
        self.claudeAPI = claudeAPI
    }

    func extractLearningNode(from completedExchange: ClicksCompletedExchange) async -> ClicksLearningNode? {
        let trimmedUserTranscript = completedExchange.userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssistantResponse = completedExchange.assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUserTranscript.isEmpty else { return nil }
        guard !trimmedAssistantResponse.isEmpty else { return nil }

        do {
            let response = try await claudeAPI.analyzeImage(
                images: [],
                systemPrompt: Self.systemPrompt,
                userPrompt: Self.userPrompt(
                    userTranscript: trimmedUserTranscript,
                    assistantResponse: trimmedAssistantResponse,
                    sourceApp: completedExchange.sourceApp
                )
            )

            guard let extractionResponse = Self.decodeExtractionResponse(from: response.text) else {
                return nil
            }

            return Self.makeLearningNode(
                from: extractionResponse,
                completedExchange: completedExchange
            )
        } catch {
            print("⚠️ Clicks extraction failed; falling back to deterministic memory.")
            return nil
        }
    }

    private static let minimumConfidenceToSave = 0.35

    private static let systemPrompt = """
    you extract local learning memories from a completed Clicky exchange.

    return only valid JSON. do not use markdown. do not include code fences.

    save only interactions where the user learned something reusable, clarified a repeated confusion, discovered a workflow, or received a useful explanation. skip purely social, empty, failed, or one-off interactions.

    expected JSON shape:
    {
      "should_save": true,
      "caption": "short title for what the user learned",
      "learning": "compact description of the actual useful learning",
      "user_intent": "what the user was trying to do",
      "source_app": "app/context if known",
      "confidence": 0.0,
      "tags": ["optional", "short"],
      "domain": "optional domain or null"
    }
    """

    private static func userPrompt(
        userTranscript: String,
        assistantResponse: String,
        sourceApp: String
    ) -> String {
        """
        source_app:
        \(sourceApp)

        user_transcript:
        \(userTranscript)

        assistant_response:
        \(assistantResponse)
        """
    }

    private static func decodeExtractionResponse(from rawResponse: String) -> ExtractionResponse? {
        let jsonString = stripAccidentalCodeFence(from: rawResponse)
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ExtractionResponse.self, from: data)
    }

    private static func stripAccidentalCodeFence(from rawResponse: String) -> String {
        var trimmedResponse = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedResponse.hasPrefix("```") {
            let responseLines = trimmedResponse.components(separatedBy: .newlines)
            trimmedResponse = responseLines
                .dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmedResponse.hasSuffix("```") {
            trimmedResponse = String(trimmedResponse.dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmedResponse
    }

    private static func makeLearningNode(
        from extractionResponse: ExtractionResponse,
        completedExchange: ClicksCompletedExchange
    ) -> ClicksLearningNode? {
        guard extractionResponse.shouldSave else { return nil }

        let confidence = clampedConfidence(extractionResponse.confidence)
        guard confidence >= minimumConfidenceToSave else { return nil }

        let caption = cappedText(extractionResponse.caption, maxCharacters: 100)
        let learning = cappedText(extractionResponse.learning, maxCharacters: 360)
        let userIntent = cappedText(extractionResponse.userIntent, maxCharacters: 240)

        guard !caption.isEmpty else { return nil }
        guard !learning.isEmpty else { return nil }

        return ClicksLearningNode(
            id: UUID(),
            createdAt: completedExchange.createdAt,
            sourceApp: sourceApp(from: extractionResponse, fallback: completedExchange.sourceApp),
            userIntent: userIntent.isEmpty ? caption : userIntent,
            caption: caption,
            learning: learning,
            confidence: confidence,
            tags: sanitizedTags(extractionResponse.tags),
            domain: cappedOptionalText(extractionResponse.domain, maxCharacters: 60)
        )
    }

    private static func sourceApp(from extractionResponse: ExtractionResponse, fallback: String) -> String {
        let extractedSourceApp = extractionResponse.sourceApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extractedSourceApp.isEmpty else {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown App" : fallback
        }

        return cappedText(extractedSourceApp, maxCharacters: 80)
    }

    private static func sanitizedTags(_ tags: [String]) -> [String] {
        var seenTags = Set<String>()
        var sanitizedTags: [String] = []

        for tag in tags {
            let sanitizedTag = cappedText(tag.lowercased(), maxCharacters: 28)
            guard !sanitizedTag.isEmpty else { continue }
            guard !seenTags.contains(sanitizedTag) else { continue }

            seenTags.insert(sanitizedTag)
            sanitizedTags.append(sanitizedTag)

            if sanitizedTags.count == 6 {
                break
            }
        }

        return sanitizedTags
    }

    private static func clampedConfidence(_ confidence: Double) -> Double {
        min(1.0, max(0.0, confidence))
    }

    private static func cappedText(_ text: String, maxCharacters: Int) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count > maxCharacters else {
            return trimmedText
        }

        return String(trimmedText.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cappedOptionalText(_ text: String?, maxCharacters: Int) -> String? {
        guard let text else { return nil }

        let cappedText = cappedText(text, maxCharacters: maxCharacters)
        return cappedText.isEmpty ? nil : cappedText
    }

    private struct ExtractionResponse: Decodable {
        let shouldSave: Bool
        let caption: String
        let learning: String
        let userIntent: String
        let sourceApp: String
        let confidence: Double
        let tags: [String]
        let domain: String?

        private enum CodingKeys: String, CodingKey {
            case shouldSave = "should_save"
            case caption
            case learning
            case userIntent = "user_intent"
            case sourceApp = "source_app"
            case confidence
            case tags
            case domain
        }
    }
}
