//
//  ClicksGraphWindowManager.swift
//  leanring-buddy
//
//  Native window lifecycle for the minimal Clicks empty state.
//

import AppKit
import SwiftUI

@MainActor
final class ClicksGraphWindowManager {
    private let clicksStore: ClicksStore
    private var panel: NSPanel?

    init(clicksStore: ClicksStore) {
        self.clicksStore = clicksStore
    }

    func showWindow() {
        if panel == nil {
            panel = makePanel()
        }

        guard let panel else { return }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let contentView = ClicksEmptyView(clicksStore: clicksStore)
        let hostingView = NSHostingView(rootView: contentView)

        let clicksPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        clicksPanel.title = "Clicks"
        clicksPanel.isFloatingPanel = false
        clicksPanel.isReleasedWhenClosed = false
        clicksPanel.minSize = NSSize(width: 640, height: 420)
        clicksPanel.collectionBehavior = [.managed, .fullScreenAuxiliary]
        clicksPanel.contentView = hostingView

        return clicksPanel
    }
}
