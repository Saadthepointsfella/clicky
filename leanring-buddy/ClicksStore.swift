//
//  ClicksStore.swift
//  leanring-buddy
//
//  Local Codable JSON store for Clicks learning memory.
//

import Foundation

struct ClicksStore {
    private static let appendQueue = DispatchQueue(label: "com.clicky.clicks-store.append")

    private let fileManager: FileManager
    private let graphFileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        self.graphFileURL = applicationSupportDirectory
            .appendingPathComponent("Clicky", isDirectory: true)
            .appendingPathComponent("Clicks", isDirectory: true)
            .appendingPathComponent("clicks.json", isDirectory: false)
    }

    func loadGraph() -> ClicksMemoryGraph {
        guard fileManager.fileExists(atPath: graphFileURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: graphFileURL)
            guard !data.isEmpty else {
                return .empty
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ClicksMemoryGraph.self, from: data)
        } catch {
            print("⚠️ ClicksStore: failed to load clicks graph: \(error.localizedDescription)")
            return .empty
        }
    }

    func saveGraph(_ graph: ClicksMemoryGraph) throws {
        let directoryURL = graphFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(graph)
        try data.write(to: graphFileURL, options: [.atomic])
    }

    func appendNode(_ node: ClicksLearningNode) throws {
        try Self.appendQueue.sync {
            var graph = loadGraph()
            graph.nodes.append(node)
            try saveGraph(graph)
        }
    }

    func replaceNode(id nodeId: UUID, with replacementNode: ClicksLearningNode) throws -> Bool {
        try Self.appendQueue.sync {
            var graph = loadGraph()
            guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeId }) else {
                return false
            }

            graph.nodes[nodeIndex] = replacementNode
            try saveGraph(graph)
            return true
        }
    }

    func updateAxisFields(
        id nodeId: UUID,
        axis: ClicksAxis?,
        axisConfidence: Double?,
        axisReason: String?
    ) throws -> Bool {
        try Self.appendQueue.sync {
            var graph = loadGraph()
            guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeId }) else {
                return false
            }

            graph.nodes[nodeIndex].axis = axis
            graph.nodes[nodeIndex].axisConfidence = axisConfidence
            graph.nodes[nodeIndex].axisReason = axisReason
            try saveGraph(graph)
            return true
        }
    }
}
