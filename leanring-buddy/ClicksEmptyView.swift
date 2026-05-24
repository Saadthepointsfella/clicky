//
//  ClicksEmptyView.swift
//  leanring-buddy
//
//  Minimal empty state for the Clicks window.
//

import SwiftUI

struct ClicksEmptyView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.98, blue: 0.94),
                    Color(red: 0.96, green: 0.94, blue: 0.89)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Text("Clicks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 0.42, green: 0.39, blue: 0.34))
                    .textCase(.uppercase)
                    .tracking(1.4)

                Text("No Clicks yet")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.12))

                Text("Enable Clicks and complete useful conversations. Saved local learnings will appear here.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.39, blue: 0.34))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 420)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.99, blue: 0.97))
                    .shadow(color: Color.black.opacity(0.10), radius: 24, x: 0, y: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(red: 0.90, green: 0.88, blue: 0.83), lineWidth: 1)
            )
            .padding(36)
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
