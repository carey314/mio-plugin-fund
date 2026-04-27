//
//  GoldPositionCard.swift
//  盯基金 plugin v0.2
//
//  「我的持仓」card under the gold chart. Mirrors the design's
//  `.gold-position` block. Tap-to-edit grams + cost-per-gram inline.
//

import SwiftUI

struct GoldPositionCard: View {
    @ObservedObject var store: FundStore
    @State private var isEditing = false
    @State private var gramsText = ""
    @State private var costText = ""
    @FocusState private var focused: Field?

    enum Field { case grams, cost }

    /// Current gold price in RMB/g (from SHFE realtime).
    private var currentPrice: Double? {
        store.goldQuotes[.shfeFutures]?.last
    }

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                display
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FundTheme.overlay04)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FundTheme.overlay08, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Display

    private var display: some View {
        let p = store.goldPosition.position
        let cur = currentPrice
        let marketValue: Double? = {
            guard let g = p.grams, let cur else { return nil }
            return g * cur
        }()
        let pnl: Double? = {
            guard let mv = marketValue, let cost = p.costAmount else { return nil }
            return mv - cost
        }()
        let pnlPct: Double? = {
            guard let pnl = pnl, let cost = p.costAmount, cost > 0 else { return nil }
            return pnl / cost * 100
        }()

        return VStack(alignment: .leading, spacing: 8) {
            if !p.hasPosition {
                // Empty state inline — encourage the user to fill in.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("我的持仓")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(FundTheme.fg55)
                        Text("点击右侧添加持仓信息")
                            .font(.system(size: 11))
                            .foregroundColor(FundTheme.fg40)
                    }
                    Spacer()
                    Button {
                        beginEdit()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(FundTheme.gold))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("我的持仓")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(FundTheme.fg55)
                    Spacer()
                    if let mv = marketValue {
                        Text("¥ \(FundFormat.unsignedMoney(mv))")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(FundTheme.fgPrimary)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(FundTheme.fg40)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let g = p.grams, let c = p.costPerGram {
                        Text("\(FundFormat.unsignedMoney(g, decimals: 2)) g · 成本 \(String(format: "%.2f", c)) / g")
                            .font(.system(size: 11.5))
                            .foregroundColor(FundTheme.fg55)
                    }
                    Spacer()
                    if let pnl, let pct = pnlPct {
                        Text("\(FundFormat.money(pnl)) · \(FundFormat.percent(pct))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.upDown(pnl))
                            .monospacedDigit()
                    } else if marketValue != nil {
                        Text("等价格刷新…")
                            .font(.system(size: 11))
                            .foregroundColor(FundTheme.fg40)
                    }
                }

                HStack(spacing: 6) {
                    Spacer()
                    Button(action: beginEdit) {
                        Text("编辑")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(FundTheme.fg55)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(Capsule().fill(FundTheme.overlay06))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("编辑黄金持仓")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FundTheme.fgPrimary)
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FundTheme.fg55)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(FundTheme.overlay06))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                inputField(label: "克数 (g)", text: $gramsText, placeholder: "50", field: .grams)
                inputField(label: "成本(元/g)", text: $costText, placeholder: "550.00", field: .cost)
            }
            HStack(spacing: 6) {
                Button(action: clear) {
                    Text("清除")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FundTheme.fg55)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(FundTheme.overlay06))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: save) {
                    Text("保存")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(FundTheme.gold))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inputField(label: String, text: Binding<String>, placeholder: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(FundTheme.fg55)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(FundTheme.fgPrimary)
                .focused($focused, equals: field)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    focused == field
                                        ? FundTheme.gold.opacity(0.5)
                                        : FundTheme.overlay08,
                                    lineWidth: 0.8
                                )
                        )
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func beginEdit() {
        let p = store.goldPosition.position
        gramsText = p.grams.map { String(format: "%.2f", $0) } ?? ""
        costText  = p.costPerGram.map { String(format: "%.2f", $0) } ?? ""
        isEditing = true
        focused = .grams
    }

    private func cancel() {
        isEditing = false
    }

    private func save() {
        let g = Double(gramsText.trimmingCharacters(in: .whitespaces))
        let c = Double(costText.trimmingCharacters(in: .whitespaces))
        let cleanG = (g.map { $0 > 0 } ?? false) ? g : nil
        let cleanC = (c.map { $0 > 0 } ?? false) ? c : nil
        store.goldPosition.update(grams: cleanG, costPerGram: cleanC)
        isEditing = false
    }

    private func clear() {
        store.goldPosition.update(grams: nil, costPerGram: nil)
        isEditing = false
    }
}
