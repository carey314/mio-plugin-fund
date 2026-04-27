//
//  GoldView.swift
//  看盘侠 plugin v0.3
//
//  「黄金」tab — Alipay-style 「国内金价」 layout:
//
//    ┌──────────────────────────────────────────────┐
//    │ 黄金99 AU9999.SGE          盘中休市 04-25     │  hero
//    │ 1040.00  +6.75  +0.65%                        │
//    │ 今开 1039.90 · 最高 1044.00 · 最低 1034.00    │
//    ├──────────────────────────────────────────────┤
//    │  intraday line chart                          │  chart
//    │  20:00 ────── 02:30/09:00 ────── 15:30        │
//    ├──────────────────────────────────────────────┤
//    │ 我的持仓                                      │  GoldPositionCard
//    └──────────────────────────────────────────────┘
//    [伦敦金 pill] [纽约金 pill]                        reference
//

import SwiftUI

struct GoldView: View {
    @ObservedObject var store: FundStore

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                hero
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                chart
                    .padding(.horizontal, 16)
                sessionAxisStrip
                    .padding(.horizontal, 16)
                GoldPositionCard(store: store)
                    .padding(.horizontal, 16)
                referencePills
                    .padding(.horizontal, 16)
                Spacer(minLength: 8)
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Hero (AU9999 spot)

    private var hero: some View {
        let q = store.spotGold
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(FundTheme.gold)
                    .frame(width: 6, height: 6)
                    .shadow(color: FundTheme.gold.opacity(0.6), radius: 4)
                Text("国内金价")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FundTheme.gold.opacity(0.85))
                    .tracking(0.5)
                Text("AU9999.SGE")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(FundTheme.fg45)
                Spacer()
                if let t = q?.updatedAt {
                    Text(timeOnly(t))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(FundTheme.fg45)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                if let q {
                    Text(String(format: "%.2f", q.last))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.upDown(q.change))
                        .monospacedDigit()
                    Text(FundFormat.money(q.change))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.upDown(q.change))
                        .monospacedDigit()
                    Text(FundFormat.percent(q.changeRate))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.upDown(q.change))
                        .monospacedDigit()
                    Spacer()
                    Text("元/克")
                        .font(.system(size: 11))
                        .foregroundColor(FundTheme.fg55)
                } else {
                    Text("--")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(FundTheme.fg40)
                    Text("加载中…")
                        .font(.system(size: 11))
                        .foregroundColor(FundTheme.fg40)
                }
            }
            .padding(.top, 1)

            if let q {
                HStack(alignment: .top, spacing: 6) {
                    metaItem("今开", String(format: "%.2f", q.open))
                    metaItem("最高", String(format: "%.2f", q.high))
                    metaItem("最低", String(format: "%.2f", q.low))
                    metaItem("昨收", String(format: "%.2f", q.prevClose))
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            FundTheme.gold.opacity(0.08),
                            FundTheme.gold.opacity(0.02)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(FundTheme.gold.opacity(0.22), lineWidth: 0.8)
                )
        )
    }

    /// Stacked vertical (label tiny on top, value below) so 4-digit
    /// values like 1039.90 don't wrap mid-number when packed across the
    /// 380pt panel.
    private func metaItem(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k)
                .font(.system(size: 9.5))
                .foregroundColor(FundTheme.fg45)
            Text(v)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(FundTheme.fgPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeOnly(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    // MARK: - Chart (intraday minute line — AU0)

    private var chart: some View {
        let prices = store.goldMinuteLine.map(\.price)
        return SparkLine(
            values: prices,
            lineColor: FundTheme.gold,
            fillColor: FundTheme.gold,
            pulseColor: FundTheme.gold
        )
        .frame(height: 110)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Session axis (replaces 1月/3月/1年/全部 with trade-session anchors)

    private var sessionAxisStrip: some View {
        HStack {
            Text("20:00")
            Spacer()
            Text("02:30 / 09:00")
            Spacer()
            Text("15:30")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(FundTheme.fg45)
        .padding(.horizontal, 6)
        .padding(.top, -2)
    }

    // MARK: - Reference pills

    private var referencePills: some View {
        HStack(spacing: 8) {
            referencePill(source: .london)
            referencePill(source: .comex)
        }
    }

    private func referencePill(source: GoldQuote.Source) -> some View {
        let q = store.goldQuotes[source]
        return VStack(alignment: .leading, spacing: 4) {
            Text(source.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(FundTheme.fg55)
            if let q {
                Text("$\(String(format: "%.2f", q.last))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                if let r = q.changeRate {
                    Text(FundFormat.percent(r))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.upDown(r))
                        .monospacedDigit()
                }
            } else {
                Text("--")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(FundTheme.fg40)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(FundTheme.overlay04)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(FundTheme.overlay08, lineWidth: 0.5)
                )
        )
    }
}
