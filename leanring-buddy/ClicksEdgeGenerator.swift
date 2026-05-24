//
//  ClicksEdgeGenerator.swift
//  leanring-buddy
//
//  Explicit on-demand semantic edge generation for Clicks memory.
//

import Foundation

struct ClicksEdgeGenerationResult {
    let edges: [ClicksLearningEdge]
    let proposedEdgeCount: Int
    let droppedEdgeCount: Int
    let shouldReplaceEdges: Bool
    let didFail: Bool

    static let noWrite = ClicksEdgeGenerationResult(
        edges: [],
        proposedEdgeCount: 0,
        droppedEdgeCount: 0,
        shouldReplaceEdges: false,
        didFail: true
    )
}

struct ClicksEdgeGenerator {
    private let claudeAPI: ClaudeAPI

    init(claudeAPI: ClaudeAPI) {
        self.claudeAPI = claudeAPI
    }

    func generateRelatedEdges(for graph: ClicksMemoryGraph) async -> ClicksEdgeGenerationResult {
        let candidateNodes = graph.nodes
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(30)
            .map { $0 }

        guard candidateNodes.count >= 2 else {
            print("edge gen: started, \(candidateNodes.count) nodes")
            return .noWrite
        }

        print("edge gen: started, \(candidateNodes.count) nodes")

        do {
            let response = try await claudeAPI.analyzeImage(
                images: [],
                systemPrompt: Self.systemPrompt,
                userPrompt: Self.userPrompt(for: candidateNodes)
            )
            print("edge gen: claude returned")

            guard let proposedResponse = Self.decodeProposedEdges(from: response.text) else {
                print("edge gen: parse failed, no edges")
                return .noWrite
            }

            print("edge gen: parsed \(proposedResponse.edges.count) proposed edges")
            return Self.validatedEdges(
                proposedEdges: proposedResponse.edges,
                currentNodes: candidateNodes
            )
        } catch {
            print("edge gen: claude threw")
            return .noWrite
        }
    }

    private static let systemPrompt = """
    Identify pairs of Clicks cards that are genuinely related by topic or subject matter.

    Rules:
    - only link cards that share a real, specific topic
    - do NOT link cards merely because they use the same app
    - do NOT link cards merely because both are questions
    - if nothing genuinely relates, return zero edges
    - use only type "related"
    - return ONLY JSON
    - no markdown
    - no prose
    - no code fences

    Expected JSON:
    {
      "edges": [
        {
          "source_id": "<uuid>",
          "target_id": "<uuid>",
          "type": "related",
          "label": "short topic-level reason",
          "confidence": 0.72
        }
      ]
    }
    """

    private static func userPrompt(for nodes: [ClicksLearningNode]) -> String {
        let compactNodes = nodes.map { node in
            [
                "id": node.id.uuidString,
                "caption": node.caption,
                "learning": node.learning,
                "sourceApp": node.sourceApp,
                "axis": node.axis?.rawValue ?? ""
            ]
        }

        let data = (try? JSONSerialization.data(
            withJSONObject: ["nodes": compactNodes],
            options: [.sortedKeys]
        )) ?? Data()

        let json = String(data: data, encoding: .utf8) ?? #"{"nodes":[]}"#
        return """
        Here are the Clicks cards to link. Use only ids from this payload.

        \(json)
        """
    }

    private static func decodeProposedEdges(from rawResponse: String) -> ProposedEdgesResponse? {
        guard let jsonString = extractJSONObjectString(from: rawResponse),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ProposedEdgesResponse.self, from: data)
    }

    private static func extractJSONObjectString(from rawResponse: String) -> String? {
        var trimmedResponse = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else { return nil }

        if trimmedResponse.hasPrefix("```") {
            trimmedResponse = trimmedResponse
                .components(separatedBy: .newlines)
                .dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmedResponse.hasSuffix("```") {
            trimmedResponse = String(trimmedResponse.dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonStartIndex = trimmedResponse.firstIndex(of: "{"),
              let jsonEndIndex = trimmedResponse.lastIndex(of: "}"),
              jsonStartIndex <= jsonEndIndex else {
            return nil
        }

        return String(trimmedResponse[jsonStartIndex...jsonEndIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validatedEdges(
        proposedEdges: [ProposedEdge],
        currentNodes: [ClicksLearningNode]
    ) -> ClicksEdgeGenerationResult {
        let nodeIds = Set(currentNodes.map(\.id))
        var seenUndirectedPairs = Set<String>()
        var validatedEdges: [ClicksLearningEdge] = []
        var droppedEdgeCount = 0

        for proposedEdge in proposedEdges {
            guard proposedEdge.type == "related" else {
                droppedEdgeCount += 1
                continue
            }

            guard let sourceNodeId = UUID(uuidString: proposedEdge.sourceId),
                  let targetNodeId = UUID(uuidString: proposedEdge.targetId),
                  nodeIds.contains(sourceNodeId),
                  nodeIds.contains(targetNodeId),
                  sourceNodeId != targetNodeId else {
                droppedEdgeCount += 1
                continue
            }

            guard proposedEdge.confidence.isFinite,
                  (0.0...1.0).contains(proposedEdge.confidence) else {
                droppedEdgeCount += 1
                continue
            }

            let sanitizedLabel = sanitizedEdgeLabel(proposedEdge.label)
            guard !sanitizedLabel.isEmpty else {
                droppedEdgeCount += 1
                continue
            }

            let pairKey = undirectedPairKey(sourceNodeId, targetNodeId)
            guard !seenUndirectedPairs.contains(pairKey) else {
                droppedEdgeCount += 1
                continue
            }
            seenUndirectedPairs.insert(pairKey)

            validatedEdges.append(
                ClicksLearningEdge(
                    id: UUID(),
                    createdAt: Date(),
                    sourceNodeId: sourceNodeId,
                    targetNodeId: targetNodeId,
                    type: .related,
                    label: sanitizedLabel,
                    confidence: proposedEdge.confidence
                )
            )
        }

        print("edge gen: \(validatedEdges.count) validated, \(droppedEdgeCount) dropped (bad ids/self/dup)")

        let shouldReplaceEdges = proposedEdges.isEmpty || !validatedEdges.isEmpty
        return ClicksEdgeGenerationResult(
            edges: validatedEdges,
            proposedEdgeCount: proposedEdges.count,
            droppedEdgeCount: droppedEdgeCount,
            shouldReplaceEdges: shouldReplaceEdges,
            didFail: false
        )
    }

    private static func undirectedPairKey(_ firstNodeId: UUID, _ secondNodeId: UUID) -> String {
        [firstNodeId.uuidString, secondNodeId.uuidString]
            .sorted()
            .joined(separator: "::")
    }

    private static func sanitizedEdgeLabel(_ label: String) -> String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return "" }

        return String(trimmedLabel.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ProposedEdgesResponse: Decodable {
        let edges: [ProposedEdge]
    }

    private struct ProposedEdge: Decodable {
        let sourceId: String
        let targetId: String
        let type: String
        let label: String
        let confidence: Double

        private enum CodingKeys: String, CodingKey {
            case sourceId = "source_id"
            case targetId = "target_id"
            case type
            case label
            case confidence
        }
    }
}
