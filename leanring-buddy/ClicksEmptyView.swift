//
//  ClicksEmptyView.swift
//  leanring-buddy
//
//  Minimal native view for local Clicks memory.
//

import SwiftUI

struct ClicksEmptyView: View {
    let clicksStore: ClicksStore
    let clicksLearningExtractor: ClicksLearningExtractor
    @State private var graph: ClicksMemoryGraph
    @State private var isImprovingLatestClick = false
    @State private var improveLatestClickStatus: String?

    init(clicksStore: ClicksStore, clicksLearningExtractor: ClicksLearningExtractor) {
        self.clicksStore = clicksStore
        self.clicksLearningExtractor = clicksLearningExtractor
        self._graph = State(initialValue: clicksStore.loadGraph())
    }

    var body: some View {
        ZStack {
            clicksWindowBackground

            VStack(alignment: .leading, spacing: 22) {
                header

                if graph.nodes.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(graph.nodes.sorted(by: { $0.createdAt > $1.createdAt })) { node in
                                ClicksLearningNodeCard(node: node)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            refreshGraph()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clicks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Self.inkSoft)
                    .textCase(.uppercase)
                    .tracking(1.4)

                Text(graph.nodes.isEmpty ? "Local learning memory" : "\(graph.nodes.count) saved learnings")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundColor(Self.ink)
            }

            Spacer()

            if !graph.nodes.isEmpty {
                Button(action: improveLatestClick) {
                    Text(isImprovingLatestClick ? "Improving..." : "Improve latest Click")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isImprovingLatestClick ? Self.inkFaint : Self.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Self.card)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Self.cardEdge, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isImprovingLatestClick)
                .pointerCursor()
            }

            Button(action: refreshGraph) {
                Text("Refresh")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Self.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Self.card)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Self.cardEdge, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .overlay(alignment: .bottomTrailing) {
            if let improveLatestClickStatus {
                Text(improveLatestClickStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Self.inkFaint)
                    .offset(y: 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No Clicks yet")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundColor(Self.ink)

            Text("Enable Clicks and complete useful conversations. Saved local learnings will appear here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Self.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 420)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Self.card)
                .shadow(color: Color.black.opacity(0.10), radius: 24, x: 0, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Self.cardEdge, lineWidth: 1)
        )
        .padding(36)
    }

    private var clicksWindowBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.98, blue: 0.94),
                Color(red: 0.96, green: 0.94, blue: 0.89)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func refreshGraph() {
        graph = clicksStore.loadGraph()
    }

    private func improveLatestClick() {
        guard !isImprovingLatestClick else { return }
        guard let latestNode = graph.nodes.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            return
        }

        isImprovingLatestClick = true
        improveLatestClickStatus = nil

        let completedExchange = ClicksCompletedExchange(
            userTranscript: latestNode.userIntent,
            assistantResponse: latestNode.learning,
            sourceApp: latestNode.sourceApp,
            createdAt: latestNode.createdAt
        )

        Task {
            let extractedNode = await clicksLearningExtractor.extractLearningNode(from: completedExchange)

            guard let extractedNode else {
                await MainActor.run {
                    isImprovingLatestClick = false
                    improveLatestClickStatus = "No stronger memory found."
                }
                return
            }

            let replacementNode = ClicksLearningNode(
                id: latestNode.id,
                createdAt: latestNode.createdAt,
                sourceApp: extractedNode.sourceApp,
                userIntent: extractedNode.userIntent,
                caption: extractedNode.caption,
                learning: extractedNode.learning,
                confidence: extractedNode.confidence,
                tags: extractedNode.tags,
                domain: extractedNode.domain
            )

            do {
                let didReplaceNode = try clicksStore.replaceNode(id: latestNode.id, with: replacementNode)
                await MainActor.run {
                    if didReplaceNode {
                        refreshGraph()
                        improveLatestClickStatus = "Latest Click improved."
                    } else {
                        improveLatestClickStatus = "Latest Click was not found."
                    }
                    isImprovingLatestClick = false
                }
            } catch {
                await MainActor.run {
                    improveLatestClickStatus = "Could not improve latest Click."
                    isImprovingLatestClick = false
                }
            }
        }
    }

    private static let ink = Color(red: 0.15, green: 0.14, blue: 0.12)
    private static let inkSoft = Color(red: 0.42, green: 0.39, blue: 0.34)
    private static let inkFaint = Color(red: 0.66, green: 0.64, blue: 0.60)
    private static let card = Color(red: 1.0, green: 0.99, blue: 0.97)
    private static let cardEdge = Color(red: 0.90, green: 0.88, blue: 0.83)
}

private struct ClicksLearningNodeCard: View {
    let node: ClicksLearningNode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.caption.isEmpty ? "Untitled learning" : node.caption)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundColor(Self.ink)

                Spacer(minLength: 12)

                Text(confidenceText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Self.inkFaint)
            }

            if !node.learning.isEmpty {
                Text(node.learning)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Self.inkSoft)
                    .lineSpacing(3)
            }

            HStack(spacing: 8) {
                metadataPill(axisText)

                if !node.sourceApp.isEmpty {
                    metadataPill(node.sourceApp)
                }

                metadataPill(createdAtText)

                if let domain = node.domain, !domain.isEmpty {
                    metadataPill(domain)
                }
            }

            if !node.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(node.tags.prefix(4), id: \.self) { tag in
                        metadataPill("#\(tag)")
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Self.card)
                .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Self.cardEdge, lineWidth: 1)
        )
    }

    private var confidenceText: String {
        "\(Int((node.confidence * 100).rounded()))%"
    }

    private var createdAtText: String {
        node.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var axisText: String {
        switch node.axis {
        case .thinking:
            return "Thinking"
        case .designing:
            return "Designing"
        case .doing:
            return "Doing"
        case nil:
            return node.axisReason == "classification_failed" ? "Unclassified" : "Classifying..."
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Self.inkSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(red: 0.94, green: 0.93, blue: 0.89))
            )
    }

    private static let ink = Color(red: 0.15, green: 0.14, blue: 0.12)
    private static let inkSoft = Color(red: 0.42, green: 0.39, blue: 0.34)
    private static let inkFaint = Color(red: 0.66, green: 0.64, blue: 0.60)
    private static let card = Color(red: 1.0, green: 0.99, blue: 0.97)
    private static let cardEdge = Color(red: 0.90, green: 0.88, blue: 0.83)
}
