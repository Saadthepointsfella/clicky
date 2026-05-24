//
//  ClicksDemoSeed.swift
//  leanring-buddy
//
//  Explicit demo-only graph seed for Clicks.
//

import Foundation

enum ClicksDemoSeed {
    static func graph() -> ClicksMemoryGraph {
        let baseDate = Date(timeIntervalSince1970: 1_790_000_000)
        let nodeIdBySeedId = Dictionary(
            uniqueKeysWithValues: seedNodes.map { ($0.seedId, $0.id) }
        )

        let nodes = seedNodes.enumerated().map { index, seedNode in
            ClicksLearningNode(
                id: seedNode.id,
                createdAt: baseDate.addingTimeInterval(TimeInterval(index * 90)),
                sourceApp: seedNode.sourceApp,
                userIntent: seedNode.userIntent,
                caption: seedNode.caption,
                learning: seedNode.learning,
                confidence: seedNode.confidence,
                tags: seedNode.tags,
                domain: seedNode.domain,
                axis: seedNode.axis,
                axisConfidence: seedNode.axisConfidence,
                axisReason: "demo_seed"
            )
        }

        let edges = seedEdges.compactMap { seedEdge -> ClicksLearningEdge? in
            guard let sourceNodeId = nodeIdBySeedId[seedEdge.sourceSeedId],
                  let targetNodeId = nodeIdBySeedId[seedEdge.targetSeedId] else {
                return nil
            }

            return ClicksLearningEdge(
                id: seedEdge.id,
                createdAt: baseDate.addingTimeInterval(TimeInterval(2_000 + seedEdge.ordinal * 60)),
                sourceNodeId: sourceNodeId,
                targetNodeId: targetNodeId,
                type: .related,
                label: seedEdge.label,
                confidence: seedEdge.confidence
            )
        }

        return ClicksMemoryGraph(nodes: nodes, edges: edges)
    }

    private static let seedNodes: [SeedNode] = [
        SeedNode(
            seedId: "n01",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111101")!,
            caption: "why event taps get disabled",
            learning: "CGEvent taps can be disabled when panel focus or main-loop work delays the callback; recovery has to be explicit.",
            sourceApp: "Xcode",
            userIntent: "Understand why push-to-talk stops after panel interactions.",
            axis: .thinking,
            axisConfidence: 0.91,
            tags: ["hotkey", "event-tap"],
            domain: "macOS"
        ),
        SeedNode(
            seedId: "n02",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111102")!,
            caption: "modifier state should self-correct",
            learning: "Deriving pressed state from current modifier flags prevents one missed release from poisoning future shortcut presses.",
            sourceApp: "Xcode",
            userIntent: "Fix stuck modifier-only push-to-talk state.",
            axis: .doing,
            axisConfidence: 0.88,
            tags: ["shortcut", "state"],
            domain: "macOS"
        ),
        SeedNode(
            seedId: "n03",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111103")!,
            caption: "fallback hotkey for demos",
            learning: "A Carbon ctrl-option-space fallback gives the demo a stable path when modifier-only event taps are unreliable.",
            sourceApp: "Xcode",
            userIntent: "Add a safer demo shortcut without changing dictation behavior.",
            axis: .doing,
            axisConfidence: 0.9,
            tags: ["carbon", "demo"],
            domain: "macOS"
        ),
        SeedNode(
            seedId: "n04",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111104")!,
            caption: "panel auto-show can disturb input",
            learning: "Returning users do not need the menu panel auto-shown on launch; skipping it avoids unnecessary focus churn.",
            sourceApp: "Claude",
            userIntent: "Reason about why launch focus changes affect hotkey reliability.",
            axis: .thinking,
            axisConfidence: 0.86,
            tags: ["panel", "startup"],
            domain: "product"
        ),
        SeedNode(
            seedId: "n05",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111105")!,
            caption: "axis should be AI-only",
            learning: "For the demo story, cards start unclassified and then get upgraded by the AI classifier instead of using fake keyword labels.",
            sourceApp: "Claude",
            userIntent: "Decide whether classification should be deterministic or AI-generated.",
            axis: .thinking,
            axisConfidence: 0.93,
            tags: ["classification", "demo"],
            domain: "Clicks"
        ),
        SeedNode(
            seedId: "n06",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111106")!,
            caption: "local-first graph assets",
            learning: "The graph UI should bundle fonts, Cytoscape, CSS, and JS locally so opening Clicks never depends on a CDN.",
            sourceApp: "Xcode",
            userIntent: "Make the Clicks graph render with no runtime network dependencies.",
            axis: .doing,
            axisConfidence: 0.89,
            tags: ["assets", "local-first"],
            domain: "Clicks"
        ),
        SeedNode(
            seedId: "n07",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111107")!,
            caption: "index cards over generic nodes",
            learning: "Ruled index cards make saved learnings feel like collected notes rather than generic graph boxes.",
            sourceApp: "Figma",
            userIntent: "Design a graph node style that feels memorable and tactile.",
            axis: .designing,
            axisConfidence: 0.92,
            tags: ["cards", "visual-system"],
            domain: "design"
        ),
        SeedNode(
            seedId: "n08",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111108")!,
            caption: "sage accent anchors the brand",
            learning: "A restrained sage accent keeps the graph warm and focused while axis colors carry semantic identity.",
            sourceApp: "Figma",
            userIntent: "Choose colors for the Clicks knowledge graph.",
            axis: .designing,
            axisConfidence: 0.9,
            tags: ["color", "brand"],
            domain: "design"
        ),
        SeedNode(
            seedId: "n09",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111109")!,
            caption: "axis zones give spatial meaning",
            learning: "Thinking, designing, and doing zones help people scan the graph by intent before reading individual cards.",
            sourceApp: "Figma",
            userIntent: "Lay out graph cards by intent categories.",
            axis: .designing,
            axisConfidence: 0.94,
            tags: ["layout", "axis"],
            domain: "design"
        ),
        SeedNode(
            seedId: "n10",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111110")!,
            caption: "HTML overlays need precise sync",
            learning: "The graph can use invisible Cytoscape nodes while HTML cards track pan and zoom through an overlay transform.",
            sourceApp: "Code",
            userIntent: "Make rich HTML cards move with graph nodes.",
            axis: .doing,
            axisConfidence: 0.91,
            tags: ["cytoscape", "webview"],
            domain: "Clicks"
        ),
        SeedNode(
            seedId: "n11",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            caption: "edges must be validated locally",
            learning: "LLM-proposed links are only safe after checking real node IDs, edge type, self-links, duplicates, and confidence.",
            sourceApp: "Claude",
            userIntent: "Design a safe semantic edge generation pass.",
            axis: .thinking,
            axisConfidence: 0.92,
            tags: ["edges", "validation"],
            domain: "Clicks"
        ),
        SeedNode(
            seedId: "n12",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111112")!,
            caption: "serial queue protects clicks.json",
            learning: "Every load-modify-save operation should use the same serial queue so rapid captures do not drop cards.",
            sourceApp: "Xcode",
            userIntent: "Prevent concurrent writes from corrupting Clicks storage.",
            axis: .doing,
            axisConfidence: 0.93,
            tags: ["storage", "concurrency"],
            domain: "Clicks"
        ),
        SeedNode(
            seedId: "n13",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111113")!,
            caption: "manual rebuild keeps edge gen safe",
            learning: "Running link generation only from an explicit button avoids surprise Claude calls during capture or window open.",
            sourceApp: "Claude",
            userIntent: "Choose a low-risk trigger for semantic links.",
            axis: .thinking,
            axisConfidence: 0.87,
            tags: ["edges", "manual"],
            domain: "Clicks"
        ),
        SeedNode(
            seedId: "n14",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111114")!,
            caption: "cream paper changes the mood",
            learning: "A warm cream field and soft shadows make the graph feel like a workspace instead of a dashboard.",
            sourceApp: "Figma",
            userIntent: "Make the graph feel editorial and warm.",
            axis: .designing,
            axisConfidence: 0.88,
            tags: ["visual-style", "paper"],
            domain: "design"
        ),
        SeedNode(
            seedId: "n15",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111115")!,
            caption: "one vertical slice proves the system",
            learning: "A single path from capture to card to axis to link validates the product story better than many partial features.",
            sourceApp: "Claude",
            userIntent: "Prioritize demo scope around an end-to-end slice.",
            axis: .thinking,
            axisConfidence: 0.9,
            tags: ["scope", "demo"],
            domain: "product"
        ),
        SeedNode(
            seedId: "n16",
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111116")!,
            caption: "visible failure beats silent loading",
            learning: "If bundled graph assets fail, the WebView should show an explicit fallback instead of a blank dark surface.",
            sourceApp: "Xcode",
            userIntent: "Debug why the Clicks graph opened blank.",
            axis: .doing,
            axisConfidence: 0.86,
            tags: ["debugging", "webview"],
            domain: "Clicks"
        )
    ]

    private static let seedEdges: [SeedEdge] = [
        SeedEdge(ordinal: 1, id: UUID(uuidString: "22222222-2222-4222-8222-222222222201")!, sourceSeedId: "n01", targetSeedId: "n02", label: "push-to-talk state recovery", confidence: 0.85),
        SeedEdge(ordinal: 2, id: UUID(uuidString: "22222222-2222-4222-8222-222222222202")!, sourceSeedId: "n01", targetSeedId: "n03", label: "shortcut reliability", confidence: 0.82),
        SeedEdge(ordinal: 3, id: UUID(uuidString: "22222222-2222-4222-8222-222222222203")!, sourceSeedId: "n01", targetSeedId: "n04", label: "panel focus and event taps", confidence: 0.78),
        SeedEdge(ordinal: 4, id: UUID(uuidString: "22222222-2222-4222-8222-222222222204")!, sourceSeedId: "n06", targetSeedId: "n10", label: "local graph rendering", confidence: 0.86),
        SeedEdge(ordinal: 5, id: UUID(uuidString: "22222222-2222-4222-8222-222222222205")!, sourceSeedId: "n06", targetSeedId: "n16", label: "WebView asset reliability", confidence: 0.8),
        SeedEdge(ordinal: 6, id: UUID(uuidString: "22222222-2222-4222-8222-222222222206")!, sourceSeedId: "n07", targetSeedId: "n08", label: "visual identity", confidence: 0.84),
        SeedEdge(ordinal: 7, id: UUID(uuidString: "22222222-2222-4222-8222-222222222207")!, sourceSeedId: "n07", targetSeedId: "n14", label: "paper card aesthetic", confidence: 0.86),
        SeedEdge(ordinal: 8, id: UUID(uuidString: "22222222-2222-4222-8222-222222222208")!, sourceSeedId: "n08", targetSeedId: "n09", label: "axis visual system", confidence: 0.81),
        SeedEdge(ordinal: 9, id: UUID(uuidString: "22222222-2222-4222-8222-222222222209")!, sourceSeedId: "n09", targetSeedId: "n10", label: "spatial graph layout", confidence: 0.77),
        SeedEdge(ordinal: 10, id: UUID(uuidString: "22222222-2222-4222-8222-222222222210")!, sourceSeedId: "n05", targetSeedId: "n11", label: "AI classification and validation", confidence: 0.79),
        SeedEdge(ordinal: 11, id: UUID(uuidString: "22222222-2222-4222-8222-222222222211")!, sourceSeedId: "n11", targetSeedId: "n13", label: "safe semantic linking", confidence: 0.88),
        SeedEdge(ordinal: 12, id: UUID(uuidString: "22222222-2222-4222-8222-222222222212")!, sourceSeedId: "n12", targetSeedId: "n13", label: "manual writes and storage safety", confidence: 0.76),
        SeedEdge(ordinal: 13, id: UUID(uuidString: "22222222-2222-4222-8222-222222222213")!, sourceSeedId: "n12", targetSeedId: "n16", label: "failure-safe persistence", confidence: 0.74),
        SeedEdge(ordinal: 14, id: UUID(uuidString: "22222222-2222-4222-8222-222222222214")!, sourceSeedId: "n05", targetSeedId: "n15", label: "demo product story", confidence: 0.83),
        SeedEdge(ordinal: 15, id: UUID(uuidString: "22222222-2222-4222-8222-222222222215")!, sourceSeedId: "n03", targetSeedId: "n15", label: "demo stability", confidence: 0.8)
    ]

    private struct SeedNode {
        let seedId: String
        let id: UUID
        let caption: String
        let learning: String
        let sourceApp: String
        let userIntent: String
        let axis: ClicksAxis
        let axisConfidence: Double
        let tags: [String]
        let domain: String
        let confidence = 0.86
    }

    private struct SeedEdge {
        let ordinal: Int
        let id: UUID
        let sourceSeedId: String
        let targetSeedId: String
        let label: String
        let confidence: Double
    }
}
