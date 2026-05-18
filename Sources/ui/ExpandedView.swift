//
//  ExpandedView.swift
//  盯基金 plugin v0.2
//
//  Top-level panel container — 380×540 to match design spec. Renders
//  the title bar (with refresh button + live dot) + tab pill strip +
//  active tab body (HoldingsView / GoldView / AddView).
//

import SwiftUI

struct ExpandedView: View {
    @ObservedObject var store: FundStore = .shared

    enum Tab: String, CaseIterable, Identifiable {
        case holdings = "持仓"
        case gold = "黄金"
        case add = "添加"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .holdings
    @State private var refreshSpinning = false

    var body: some View {
        VStack(spacing: 0) {
            // Notch reservation strip (40pt) — same pattern Music Player
            // uses. The physical camera/notch module + the host's
            // floating back-chevron (at y=12, host-controlled) live in
            // this band. No plugin paint here so the dark Island shell
            // shows through cleanly behind the notch.
            Color.clear.frame(height: 40)
            topBar
            tabStrip
            body_
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: 380, height: 580)
        .background(
            ZStack {
                FundTheme.panelBg
                // very subtle radial highlight at the top to feel like the
                // notch glow rolling onto the panel
                RadialGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    center: .top,
                    startRadius: 4, endRadius: 220
                )
            }
        )
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: 28, bottomTrailing: 28, topTrailing: 0)
            )
        )
        // Mount the toast + confirm layers at the plugin root so any
        // view in the tree can call ToastController.shared.success(...)
        // or `await ConfirmController.shared.ask(...)` without threading
        // state through props.
        .toastOverlay()
        .confirmOverlay()
        .onAppear {
            store.start()
            Task { await store.refreshNow() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // The notch strip above (40pt) already clears the host's
            // floating back-chevron, so the title can sit flush at the
            // panel's leading edge — no horizontal indent needed.
            HStack(spacing: 8) {
                Circle()
                    .fill(FundTheme.lime)
                    .frame(width: 7, height: 7)
                    .shadow(color: FundTheme.lime.opacity(0.6), radius: 4)
                Text("看盘侠")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FundTheme.fgPrimary)
            }
            Spacer()

            // Refresh button
            Button {
                refreshSpinning = true
                Task {
                    await store.refreshNow()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    refreshSpinning = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(refreshSpinning ? FundTheme.lime : FundTheme.fg55)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.clear))
                    .rotationEffect(.degrees(refreshSpinning ? 360 : 0))
                    .animation(.easeInOut(duration: 0.6), value: refreshSpinning)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Tabs

    private var tabStrip: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { t in
                tabPill(label: t.rawValue, count: count(for: t), selected: tab == t) {
                    tab = t
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func tabPill(label: String, count: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                if let c = count {
                    Text("\(c)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .opacity(selected ? 0.55 : 0.7)
                        .monospacedDigit()
                }
            }
            .foregroundColor(selected ? Color(red: 0x0B/255, green: 0x0B/255, blue: 0x0B/255) : FundTheme.fg70)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(selected ? FundTheme.lime : FundTheme.overlay04)
                    .overlay(
                        Capsule()
                            .stroke(selected ? Color.clear : FundTheme.overlay08, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func count(for tab: Tab) -> Int? {
        switch tab {
        case .holdings: return store.watchlist.funds.count
        default: return nil
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var body_: some View {
        switch tab {
        case .holdings:
            HoldingsView(store: store) { tab = .add }
        case .gold:
            GoldView(store: store)
        case .add:
            AddView(store: store)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                LiveDot()
                Text(footerLeftText)
            }
            Spacer()
            Text(footerRightText)
        }
        .font(.system(size: 11))
        .foregroundColor(FundTheme.fg40)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Rectangle()
                        .fill(FundTheme.overlay04)
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }

    private var footerLeftText: String {
        switch tab {
        case .holdings: return store.estimates.isEmpty ? "等待数据..." : "实时估值"
        case .gold:     return "沪金 SHFE"
        case .add:      return "东方财富搜索"
        }
    }

    private var footerRightText: String {
        if let t = lastUpdate {
            return "更新于 \(relative(t))"
        }
        return "—"
    }

    private var lastUpdate: Date? {
        switch tab {
        case .holdings: return store.lastFundRefresh
        case .gold:     return store.lastGoldRefresh
        case .add:      return nil
        }
    }

    private func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s)s 前" }
        if s < 3600 { return "\(s / 60)分前" }
        return "\(s / 3600)时前"
    }
}

// MARK: - Live dot (small pulsing green dot, copied from design)

private struct LiveDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(FundTheme.downGreen)
            .frame(width: 6, height: 6)
            .shadow(color: FundTheme.downGreen.opacity(0.7), radius: 4)
            .scaleEffect(pulse ? 0.8 : 1.0)
            .opacity(pulse ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
