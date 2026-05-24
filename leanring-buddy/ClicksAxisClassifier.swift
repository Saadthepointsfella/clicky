//
//  ClicksAxisClassifier.swift
//  leanring-buddy
//
//  Local deterministic classifier for Clicks axis metadata.
//

import Foundation

struct ClicksAxisClassification {
    let axis: ClicksAxis
    let confidence: Double
    let reason: String
}

enum ClicksAxisClassifier {
    static func classify(userIntent: String, sourceApp: String?) -> ClicksAxisClassification {
        let normalizedUserIntent = normalize(userIntent)
        let normalizedSourceApp = normalize(sourceApp ?? "")

        let intentScores = axisScores(
            for: normalizedUserIntent,
            keywordGroups: intentKeywordGroups
        )
        let sourceAppAxis = axisForSourceApp(normalizedSourceApp)

        if let intentAxis = strongestAxis(from: intentScores) {
            if let sourceAppAxis, sourceAppAxis == intentAxis {
                return ClicksAxisClassification(
                    axis: intentAxis,
                    confidence: 0.9,
                    reason: "intent_tool_aligned"
                )
            }

            if sourceAppAxis != nil, sourceAppAxis != intentAxis {
                return ClicksAxisClassification(
                    axis: intentAxis,
                    confidence: 0.6,
                    reason: "intent_tool_conflict"
                )
            }

            return ClicksAxisClassification(
                axis: intentAxis,
                confidence: 0.75,
                reason: intentReason(for: intentAxis)
            )
        }

        if let sourceAppAxis {
            return ClicksAxisClassification(
                axis: sourceAppAxis,
                confidence: 0.65,
                reason: toolReason(for: sourceAppAxis)
            )
        }

        return ClicksAxisClassification(
            axis: .thinking,
            confidence: 0.45,
            reason: "unclear_default_thinking"
        )
    }

    private static let intentKeywordGroups: [ClicksAxis: [String]] = [
        .thinking: [
            "explain",
            "understand",
            "why",
            "what is",
            "analyze",
            "compare",
            "reason",
            "learn",
            "summarize",
            "interpret",
            "think",
            "theory",
            "concept"
        ],
        .designing: [
            "design",
            "mockup",
            "visual",
            "layout",
            "color",
            "typography",
            "brand",
            "ui",
            "ux",
            "image",
            "style",
            "prompt",
            "aesthetic",
            "wireframe"
        ],
        .doing: [
            "implement",
            "fix",
            "debug",
            "build",
            "run",
            "ship",
            "code",
            "commit",
            "test",
            "deploy",
            "create file",
            "terminal",
            "error",
            "compile"
        ]
    ]

    private static let sourceAppGroups: [ClicksAxis: [String]] = [
        .thinking: [
            "safari",
            "chrome",
            "arc",
            "notes",
            "preview",
            "books",
            "notion",
            "obsidian",
            "chatgpt",
            "claude"
        ],
        .designing: [
            "figma",
            "figjam",
            "sketch",
            "canva",
            "photoshop",
            "illustrator",
            "framer"
        ],
        .doing: [
            "xcode",
            "vs code",
            "visual studio code",
            "code",
            "cursor",
            "terminal",
            "iterm",
            "warp",
            "github desktop",
            "tableplus",
            "postman",
            "numbers",
            "excel"
        ]
    ]

    private static func axisScores(
        for text: String,
        keywordGroups: [ClicksAxis: [String]]
    ) -> [ClicksAxis: Int] {
        var scores: [ClicksAxis: Int] = [:]

        for (axis, keywords) in keywordGroups {
            let matchingKeywordCount = keywords.reduce(0) { count, keyword in
                text.contains(keyword) ? count + 1 : count
            }
            scores[axis] = matchingKeywordCount
        }

        return scores
    }

    private static func strongestAxis(from scores: [ClicksAxis: Int]) -> ClicksAxis? {
        let sortedScores = scores.sorted { leftScore, rightScore in
            if leftScore.value == rightScore.value {
                return axisPriority(leftScore.key) < axisPriority(rightScore.key)
            }

            return leftScore.value > rightScore.value
        }

        guard let strongestScore = sortedScores.first else { return nil }
        guard strongestScore.value > 0 else { return nil }

        let secondScore = sortedScores.dropFirst().first?.value ?? 0
        guard strongestScore.value > secondScore else { return nil }

        return strongestScore.key
    }

    private static func axisForSourceApp(_ sourceApp: String) -> ClicksAxis? {
        guard !sourceApp.isEmpty else { return nil }

        for (axis, appNames) in sourceAppGroups {
            if appNames.contains(where: { sourceApp.contains($0) }) {
                return axis
            }
        }

        return nil
    }

    private static func intentReason(for axis: ClicksAxis) -> String {
        switch axis {
        case .thinking:
            return "intent_thinking"
        case .designing:
            return "intent_designing"
        case .doing:
            return "intent_doing"
        }
    }

    private static func toolReason(for axis: ClicksAxis) -> String {
        switch axis {
        case .thinking:
            return "tool_thinking"
        case .designing:
            return "tool_designing"
        case .doing:
            return "tool_doing"
        }
    }

    private static func axisPriority(_ axis: ClicksAxis) -> Int {
        switch axis {
        case .thinking:
            return 0
        case .designing:
            return 1
        case .doing:
            return 2
        }
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
