//
//  PositionEditor.swift
//  盯基金 plugin v0.2
//
//  Inline editor for a holding's shares + cost basis. Opened from the
//  holding row's "edit" button, dismissed by Save / Cancel.
//
//  Why inline (rather than a separate window): plugins can't open NSWindows
//  cleanly without going through the host. Inline editing inside the
//  panel keeps the experience contained — and the user is already
//  looking at this row.
//

import SwiftUI

struct PositionEditor: View {
    let fund: WatchlistFund
    let onSave: (Double?, Double?) -> Void
    let onCancel: () -> Void

    @State private var sharesText: String = ""
    @State private var costText: String = ""
    @FocusState private var focused: Field?

    enum Field { case shares, cost }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("编辑持仓")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FundTheme.fgPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FundTheme.fg55)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(FundTheme.overlay06))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                inputField(
                    label: "持仓份额",
                    text: $sharesText,
                    placeholder: "0",
                    field: .shares
                )
                inputField(
                    label: "成本(元/份)",
                    text: $costText,
                    placeholder: "1.0000",
                    field: .cost
                )
            }

            HStack(spacing: 6) {
                Button(action: clear) {
                    Text("清除")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FundTheme.fg55)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(FundTheme.overlay06)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: save) {
                    Text("保存")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(FundTheme.lime))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FundTheme.overlay06)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FundTheme.lime.opacity(0.18), lineWidth: 0.8)
                )
        )
        .onAppear {
            // Pre-fill if values already exist
            if let s = fund.shares { sharesText = String(format: "%.2f", s) }
            if let c = fund.costNav { costText = String(format: "%.4f", c) }
            focused = .shares
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
                                        ? FundTheme.lime.opacity(0.5)
                                        : FundTheme.overlay08,
                                    lineWidth: 0.8
                                )
                        )
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let shares = Double(sharesText.trimmingCharacters(in: .whitespaces))
        let cost = Double(costText.trimmingCharacters(in: .whitespaces))
        // Treat 0 / negative as "clear" too.
        let cleanShares = (shares.map { $0 > 0 } ?? false) ? shares : nil
        let cleanCost = (cost.map { $0 > 0 } ?? false) ? cost : nil
        onSave(cleanShares, cleanCost)
    }

    private func clear() {
        onSave(nil, nil)
    }
}
