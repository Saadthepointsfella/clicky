//
//  ClicksLearningModels.swift
//  leanring-buddy
//
//  Minimal local data model for Clicks learning memory.
//

import Foundation

struct ClicksMemoryGraph: Codable, Equatable {
    var nodes: [ClicksLearningNode]
    var edges: [ClicksLearningEdge]

    static let empty = ClicksMemoryGraph(nodes: [], edges: [])
}

enum ClicksAxis: String, Codable, Equatable, CaseIterable {
    case thinking
    case designing
    case doing
}

struct ClicksLearningNode: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var sourceApp: String
    var userIntent: String
    var caption: String
    var learning: String
    var confidence: Double
    var tags: [String]
    var domain: String?
    var axis: ClicksAxis?
    var axisConfidence: Double?
    var axisReason: String?

    init(
        id: UUID,
        createdAt: Date,
        sourceApp: String,
        userIntent: String,
        caption: String,
        learning: String,
        confidence: Double,
        tags: [String],
        domain: String?,
        axis: ClicksAxis? = nil,
        axisConfidence: Double? = nil,
        axisReason: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceApp = sourceApp
        self.userIntent = userIntent
        self.caption = caption
        self.learning = learning
        self.confidence = confidence
        self.tags = tags
        self.domain = domain
        self.axis = axis
        self.axisConfidence = Self.validAxisConfidence(axisConfidence)
        self.axisReason = Self.validAxisReason(axisReason)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceApp = try container.decode(String.self, forKey: .sourceApp)
        userIntent = try container.decode(String.self, forKey: .userIntent)
        caption = try container.decode(String.self, forKey: .caption)
        learning = try container.decode(String.self, forKey: .learning)
        confidence = try container.decode(Double.self, forKey: .confidence)
        tags = try container.decode([String].self, forKey: .tags)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)

        axis = (try? container.decodeIfPresent(ClicksAxis.self, forKey: .axis)) ?? nil
        axisConfidence = Self.validAxisConfidence(
            (try? container.decodeIfPresent(Double.self, forKey: .axisConfidence)) ?? nil
        )
        axisReason = Self.validAxisReason(
            (try? container.decodeIfPresent(String.self, forKey: .axisReason)) ?? nil
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sourceApp, forKey: .sourceApp)
        try container.encode(userIntent, forKey: .userIntent)
        try container.encode(caption, forKey: .caption)
        try container.encode(learning, forKey: .learning)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(domain, forKey: .domain)
        try container.encodeIfPresent(axis, forKey: .axis)
        try container.encodeIfPresent(axisConfidence, forKey: .axisConfidence)
        try container.encodeIfPresent(axisReason, forKey: .axisReason)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case sourceApp
        case userIntent
        case caption
        case learning
        case confidence
        case tags
        case domain
        case axis
        case axisConfidence
        case axisReason
    }

    private static func validAxisConfidence(_ confidence: Double?) -> Double? {
        guard let confidence, confidence.isFinite, (0.0...1.0).contains(confidence) else {
            return nil
        }

        return confidence
    }

    private static func validAxisReason(_ reason: String?) -> String? {
        guard let reason else { return nil }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedReason.isEmpty ? nil : trimmedReason
    }
}

struct ClicksLearningEdge: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var sourceNodeId: UUID
    var targetNodeId: UUID
    var type: ClicksLearningEdgeType
    var label: String
    var confidence: Double
}

enum ClicksLearningEdgeType: String, Codable, CaseIterable {
    case ledTo = "led_to"
    case buildsOn = "builds_on"
    case sameDomain = "same_domain"
    case repeatedConfusion = "repeated_confusion"
    case prerequisite
    case related
}
