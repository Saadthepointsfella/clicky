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
