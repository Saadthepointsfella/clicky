//
//  ClicksGraphView.swift
//  leanring-buddy
//
//  WKWebView bridge for the bundled local Clicks graph UI.
//

import SwiftUI
import WebKit

struct ClicksGraphView: NSViewRepresentable {
    let clicksStore: ClicksStore

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "seedDemoGraph")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(true, forKey: "drawsBackground")
        context.coordinator.clicksStore = clicksStore
        context.coordinator.webView = webView

        if let graphIndexURL = Self.graphIndexURL() {
            let graphAssetsDirectoryURL = graphIndexURL.deletingLastPathComponent()
            webView.loadFileURL(
                graphIndexURL,
                allowingReadAccessTo: graphAssetsDirectoryURL
            )
        } else {
            print("clicks graph: assets missing")
            webView.loadHTMLString(Self.fallbackHTML(message: "Clicks graph assets could not be loaded."), baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let payload = ClicksGraphPayload(graph: clicksStore.loadGraph())
        context.coordinator.render(payload, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var clicksStore: ClicksStore?
        weak var webView: WKWebView?
        private var hasFinishedLoadingGraphAssets = false
        private var pendingRenderScript: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasFinishedLoadingGraphAssets = true
            print("clicks graph: page loaded")
            if let pendingRenderScript {
                evaluateRenderScript(pendingRenderScript, in: webView)
                self.pendingRenderScript = nil
            }
        }

        fileprivate func render(_ payload: ClicksGraphPayload, in webView: WKWebView) {
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }

            let renderScript = """
            (function() {
              if (typeof window.renderClicksGraph !== 'function') {
                document.body.innerHTML = '<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fcf9f1;color:#1c1c17;font:16px sans-serif;">Clicks graph renderer is unavailable.</div>';
                return 'missing-renderer';
              }
              window.renderClicksGraph(\(json));
              return 'ok';
            })();
            """
            guard hasFinishedLoadingGraphAssets else {
                pendingRenderScript = renderScript
                return
            }

            evaluateRenderScript(renderScript, in: webView)
        }

        private func evaluateRenderScript(_ renderScript: String, in webView: WKWebView) {
            print("clicks graph: injecting payload")
            webView.evaluateJavaScript(renderScript) { result, error in
                if error != nil || (result as? String) == "missing-renderer" {
                    print("clicks graph: render failed")
                } else {
                    print("clicks graph: render succeeded")
                }
            }
        }
    }

    private static func graphIndexURL() -> URL? {
        let candidateSubdirectories = [
            "ClicksGraphAssets",
            "leanring-buddy/ClicksGraphAssets"
        ]

        for candidateSubdirectory in candidateSubdirectories {
            if let graphIndexURL = Bundle.main.url(
                forResource: "index",
                withExtension: "html",
                subdirectory: candidateSubdirectory
            ) {
                return graphIndexURL
            }
        }

        return Bundle.main.url(forResource: "index", withExtension: "html")
    }

    private static func fallbackHTML(message: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {
              margin: 0;
              min-height: 100vh;
              display: flex;
              align-items: center;
              justify-content: center;
              background: #fcf9f1;
              color: #1c1c17;
              font: 16px sans-serif;
            }
          </style>
        </head>
        <body>\(message)</body>
        </html>
        """
    }
}

extension ClicksGraphView.Coordinator: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "seedDemoGraph",
              let webView,
              let clicksStore else {
            return
        }

        do {
            let demoGraph = ClicksDemoSeed.graph()
            try clicksStore.replaceGraph(demoGraph)
            render(ClicksGraphPayload(graph: demoGraph), in: webView)
            print("clicks graph: demo graph seeded")
        } catch {
            print("clicks graph: demo graph seed failed")
        }
    }
}

private struct ClicksGraphPayload: Encodable {
    let nodes: [ClicksGraphNodePayload]
    let edges: [ClicksGraphEdgePayload]

    init(graph: ClicksMemoryGraph) {
        self.nodes = graph.nodes.map(ClicksGraphNodePayload.init(node:))
        self.edges = graph.edges.map(ClicksGraphEdgePayload.init(edge:))
    }
}

private struct ClicksGraphNodePayload: Encodable {
    let id: String
    let caption: String
    let learning: String
    let sourceApp: String
    let axis: String?

    init(node: ClicksLearningNode) {
        self.id = node.id.uuidString
        self.caption = node.caption
        self.learning = node.learning
        self.sourceApp = node.sourceApp
        self.axis = node.axis?.rawValue
    }
}

private struct ClicksGraphEdgePayload: Encodable {
    let id: String
    let source: String
    let target: String
    let reason: String

    init(edge: ClicksLearningEdge) {
        self.id = edge.id.uuidString
        self.source = edge.sourceNodeId.uuidString
        self.target = edge.targetNodeId.uuidString
        self.reason = edge.label
    }
}
