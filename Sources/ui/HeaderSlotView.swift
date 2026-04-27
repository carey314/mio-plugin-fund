//
//  HeaderSlotView.swift
//  盯基金 plugin
//
//  20×20 icon that lives in the notch header bar. We can't fit text
//  in 20pt, so the visual contract is: solid icon = idle / red icon
//  = portfolio down today / green icon = portfolio up today. Tap
//  opens the expanded panel.
//

import SwiftUI

struct HeaderSlotView: View {
    @ObservedObject var store: FundStore = .shared

    var body: some View {
        ZStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
        }
    }

    /// Composite tint: bias toward red/green when the day's average
    /// estimated rate across watchlist funds has a sign. Falls back
    /// to white when no estimates yet (e.g. first launch, off-hours).
    private var tint: Color {
        let rates = store.estimates.values.compactMap { $0.estimatedRate }
        guard !rates.isEmpty else { return .white.opacity(0.85) }
        let avg = rates.reduce(0, +) / Double(rates.count)
        if avg > 0.05 {
            // Chinese convention: red = up.
            return Color(red: 1.0, green: 0.30, blue: 0.30)
        } else if avg < -0.05 {
            // Green = down.
            return Color(red: 0.20, green: 0.80, blue: 0.40)
        }
        return .white.opacity(0.85)
    }
}
