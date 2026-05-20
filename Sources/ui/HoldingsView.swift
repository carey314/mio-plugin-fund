//
//  HoldingsView.swift
//  盯基金 plugin v0.2
//
//  「持仓」tab. Hero card with 总市值 + 今日盈亏 / 累计盈亏 / 收益率,
//  followed by a scrollable list of fund rows. Falls back to an
//  "empty state" when no funds are added (matches design).
//

import SwiftUI

struct HoldingsView: View {
    @ObservedObject var store: FundStore
    let onAddTap: () -> Void
    @State private var editingCode: String? = nil

    var body: some View {
        if store.watchlist.funds.isEmpty {
            emptyState
        } else {
            content
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(FundTheme.overlay04)
                    .frame(width: 48, height: 48)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundColor(FundTheme.fg45)
            }
            Text("还没添加自选基金")
                .font(.system(size: 12.5))
                .foregroundColor(FundTheme.fg35)
            Button(action: onAddTap) {
                Text("去添加")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 30)
                    .background(Capsule().fill(FundTheme.lime))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero + list

    private var content: some View {
        VStack(spacing: 0) {
            heroCard
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            columnHeader
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.watchlist.funds) { f in
                        VStack(spacing: 6) {
                            HoldingRow(
                                fund: f,
                                estimate: store.estimates[f.code],
                                onTap: {
                                    editingCode = (editingCode == f.code) ? nil : f.code
                                },
                                onRemove: {
                                    Task { @MainActor in
                                        // Danger confirm before destructive remove.
                                        // The user's only "trash" affordance is the
                                        // hover-only ✕ button so a wrong click is
                                        // possible — surface a clear ack-or-bail.
                                        let ok = await ConfirmController.shared.ask(
                                            title: "移除自选基金?",
                                            message: "「\(f.name)」(\(f.code)) 将从自选中移除,已填写的持仓份额与成本也会一并删除。",
                                            confirmLabel: "移除",
                                            cancelLabel: "取消",
                                            danger: true
                                        )
                                        guard ok else { return }
                                        if editingCode == f.code { editingCode = nil }
                                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                                            store.watchlist.remove(code: f.code)
                                        }
                                        ToastController.shared.success("已移除「\(f.name)」")
                                    }
                                }
                            )
                            if editingCode == f.code {
                                PositionEditor(
                                    fund: f,
                                    onSave: { shares, cost in
                                        store.watchlist.updatePosition(
                                            code: f.code, shares: shares, costNav: cost
                                        )
                                        editingCode = nil
                                        // Bias the message toward what the user
                                        // just did — saving with values is "已保存
                                        // 持仓",saving with both cleared is "已清
                                        // 除持仓"。Either path lands here so we
                                        // disambiguate by inputs.
                                        if shares == nil && cost == nil {
                                            ToastController.shared.info("已清除「\(f.name)」的持仓")
                                        } else {
                                            ToastController.shared.success("已保存「\(f.name)」的持仓")
                                        }
                                    },
                                    onCancel: { editingCode = nil }
                                )
                                .padding(.horizontal, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, 8)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                }
                .padding(.bottom, 4)
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: store.watchlist.funds.map(\.code))
                .animation(.easeInOut(duration: 0.2), value: editingCode)
            }
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        let mv = store.totalMarketValue
        let cost = store.totalCost
        let day = store.totalDayPnL
        let total: Double? = {
            guard let mv, let cost else { return nil }
            return mv - cost
        }()
        let totalRate: Double? = {
            guard let total, let cost, cost > 0 else { return nil }
            return total / cost * 100
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Text(mv == nil ? "自选监控" : "总市值")
                .font(.system(size: 11))
                .foregroundColor(FundTheme.fg55)
                .tracking(0.3)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                if let mv {
                    Text("¥ \(FundFormat.unsignedMoney(mv))")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(FundTheme.fgPrimary)
                        .monospacedDigit()
                    Text("CNY")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(FundTheme.fg55)
                } else {
                    Text("\(store.watchlist.funds.count) 只基金")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(FundTheme.fgPrimary)
                    Text("· 添加持仓查看盈亏")
                        .font(.system(size: 11))
                        .foregroundColor(FundTheme.fg45)
                }
            }

            if mv != nil {
                HStack(spacing: 18) {
                    statBlock(label: "今日盈亏", value: day)
                    statBlock(label: "累计盈亏", value: total)
                    statBlock(label: "收益率", value: totalRate, isPercent: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            FundTheme.lime.opacity(0.10),
                            FundTheme.lime.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(FundTheme.lime.opacity(0.18), lineWidth: 0.8)
                )
        )
    }

    /// Column header strip aligning with HoldingRow's two stat columns.
    /// Without it the user can't tell which number is 今日 vs 累计 — both
    /// look identical in a single row, and 养基宝 uses the same affordance.
    private var columnHeader: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Text("今日")
                .frame(width: 80, alignment: .trailing)
            Text("累计")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 10))
        .foregroundColor(FundTheme.fg45)
    }

    private func statBlock(label: String, value: Double?, isPercent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(FundTheme.fg45)
            if let v = value {
                Text(isPercent ? FundFormat.percent(v) : FundFormat.money(v))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.upDown(v))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FundTheme.fg40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Holding row

private struct HoldingRow: View {
    let fund: WatchlistFund
    let estimate: FundEstimate?
    let onTap: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            content
        }
        .buttonStyle(.plain)
    }

    /// Three-column layout matching 养基宝:
    ///   [name + ¥market value · 实时价]   [当日 ¥ / %]   [累计 ¥ / %]
    /// When no position is set, left side falls back to code · NAV and
    /// the 累计 column is hidden (no cost basis to compute against).
    private var content: some View {
        HStack(alignment: .center, spacing: 8) {
            // Left: name + market value (or code) · realtime nav
            VStack(alignment: .leading, spacing: 3) {
                Text(fund.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FundTheme.fgPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if let mv = marketValue {
                        Text("¥ \(FundFormat.unsignedMoney(mv))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(FundTheme.fg55)
                            .monospacedDigit()
                    } else {
                        Text(fund.code)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(FundTheme.fg40)
                    }
                    if let nav = estimate?.bestNav, nav > 0 {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(FundTheme.fg35)
                        Text(FundFormat.nav(nav))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(FundTheme.fg45)
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Middle: 当日 (today's gain). Always rendered; falls back
            // to em-dash when estimate is missing so columns stay aligned
            // with the header strip above the list.
            statColumn(amount: todayPnL, rate: estimate?.estimatedRate)

            // Right: 累计 (cumulative). Always rendered for column
            // alignment — shows a dim em-dash when the user hasn't
            // entered cost basis yet so the user knows where to look
            // once they fill it in.
            statColumn(amount: cumulativePnL, rate: cumulativeRate)

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(FundTheme.fg45)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? FundTheme.overlay04 : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    /// One stat column: ¥ amount on top (large bold), % rate below
    /// (small). When ¥ is unavailable (no position) but rate is known,
    /// promote the rate to the headline slot. When neither is known,
    /// dim em-dashes preserve column alignment with the header strip.
    /// Width 80pt so 5-digit ¥ amounts like "+4,329.79" don't truncate.
    @ViewBuilder
    private func statColumn(amount: Double?, rate: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let a = amount {
                Text(FundFormat.money(a))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.upDown(a))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let r = rate {
                    Text(FundFormat.percent(r))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.upDown(r))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            } else if let r = rate {
                Text(FundFormat.percent(r))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.upDown(r))
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FundTheme.fg35)
            }
        }
        .frame(width: 80, alignment: .trailing)
    }

    // MARK: - Computed P&L

    /// Today's market value = shares × current best NAV.
    /// Nil when shares unset (we won't show ¥ holding amount then).
    private var marketValue: Double? {
        guard let shares = fund.shares, shares > 0,
              let est = estimate, est.bestNav > 0 else { return nil }
        return shares * est.bestNav
    }

    /// Today's ¥ P&L: shares × (intraday est nav - last published nav).
    private var todayPnL: Double? {
        guard let shares = fund.shares, shares > 0 else { return nil }
        guard let est = estimate else { return nil }
        let estNav = est.estimatedNav ?? est.publishedNav
        return (estNav - est.publishedNav) * shares
    }

    /// Cumulative ¥ P&L: shares × (current best nav - cost basis).
    private var cumulativePnL: Double? {
        guard let shares = fund.shares, let cost = fund.costNav,
              let est = estimate else { return nil }
        return (est.bestNav - cost) * shares
    }

    /// Cumulative % return: (current - cost) / cost × 100.
    private var cumulativeRate: Double? {
        guard let cost = fund.costNav, cost > 0,
              let est = estimate else { return nil }
        return (est.bestNav - cost) / cost * 100
    }
}
