//
//  ClicksStore.swift
//  leanring-buddy
//
//  Local Codable JSON store for Clicks learning memory.
//

import Foundation

struct ClicksStore {
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
        var graph = loadGraph()
        graph.nodes.append(node)
        try saveGraph(graph)
    }
}
