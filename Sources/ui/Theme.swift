//
//  Theme.swift
//  盯基金 plugin v0.2
//
//  Single source of truth for the design's colour tokens. Keeps the
//  per-view code from re-deriving the same hex values.
//

import SwiftUI

enum FundTheme {
    // Lime accent — same value as the design's `#d4ff3a`.
    static let lime = Color(red: 0xD4/255, green: 0xFF/255, blue: 0x3A/255)

    // Gold accent for the gold hero card and chart.
    static let gold = Color(red: 0xFF/255, green: 0xC4/255, blue: 0x54/255)

    // China convention: red = up, green = down.
    static let upRed = Color(red: 0xFF/255, green: 0x5E/255, blue: 0x5E/255)
    static let downGreen = Color(red: 0x2C/255, green: 0xD4/255, blue: 0x7E/255)

    // Panel background — pure black with a hint of warmth.
    static let panelBg = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)

    // Subtle white overlays used everywhere.
    static let overlay04 = Color.white.opacity(0.04)
    static let overlay06 = Color.white.opacity(0.06)
    static let overlay08 = Color.white.opacity(0.08)
    static let overlay12 = Color.white.opacity(0.12)
    static let overlay18 = Color.white.opacity(0.18)

    // Foreground tints
    static let fgPrimary = Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF5/255)
    static let fg85 = Color.white.opacity(0.85)
    static let fg70 = Color.white.opacity(0.7)
    static let fg55 = Color.white.opacity(0.55)
    static let fg45 = Color.white.opacity(0.45)
    static let fg40 = Color.white.opacity(0.4)
    static let fg35 = Color.white.opacity(0.35)
}

// MARK: - Color helper

extension Color {
    /// Pick red/green based on a signed value. `0` returns a neutral white.
    /// Chinese convention: positive = red, negative = green.
    static func upDown(_ value: Double) -> Color {
        if value > 0.0001 { return FundTheme.upRed }
        if value < -0.0001 { return FundTheme.downGreen }
        return FundTheme.fg70
    }
}

// MARK: - Number formatting

enum FundFormat {
    /// "+0.53%" / "-1.20%" / "0.00%"
    static func percent(_ value: Double, decimals: Int = 2) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.\(decimals)f", value))%"
    }

    /// "+1,234.56" / "-1,234.56" / "0.00"
    static func money(_ value: Double, decimals: Int = 2) -> String {
        let sign = value > 0 ? "+" : ""
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let abs = formatter.string(from: NSNumber(value: Swift.abs(value))) ?? "0"
        if value < 0 { return "-\(abs)" }
        return "\(sign)\(abs)"
    }

    /// "1,234.56" — no sign, used for "总市值"-like displays.
    static func unsignedMoney(_ value: Double, decimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// "1.7669" — fixed decimals for NAV display.
    static func nav(_ value: Double, decimals: Int = 4) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
