//
//  AddView.swift
//  盯基金 plugin v0.2
//
//  「添加」tab. Search field + scrollable list of hits with category
//  tag, code, and an add button. Mirrors the design's panel-add.jsx
//  but uses the live Eastmoney suggest API instead of mock data.
//

import SwiftUI

struct AddView: View {
    @ObservedObject var store: FundStore
    @State private var query = ""
    @State private var hits: [FundSearchHit] = []
    @State private var isSearching = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            sectionTitle
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 4)
            list
        }
    }

    private var searchField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(FundTheme.overlay06)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(FundTheme.overlay08, lineWidth: 0.5)
                )
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FundTheme.fg40)
                TextField("搜索基金代码 / 名称", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                if isSearching {
                    ProgressView().scaleEffect(0.5)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            let q = newValue
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await runSearch(q)
            }
        }
    }

    private var sectionTitle: some View {
        HStack {
            Text(query.isEmpty ? "添加你的基金" : "搜索结果")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(FundTheme.fg40)
                .tracking(0.5)
            Spacer()
        }
    }

    @ViewBuilder
    private var list: some View {
        if query.isEmpty {
            VStack(spacing: 12) {
                Spacer().frame(height: 30)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundColor(FundTheme.fg35)
                    .padding(20)
                    .background(Circle().fill(FundTheme.overlay04))
                Text("输入基金代码或名称开始搜索")
                    .font(.system(size: 12))
                    .foregroundColor(FundTheme.fg40)
                Text("数据源: 东方财富 fund.eastmoney.com")
                    .font(.system(size: 10))
                    .foregroundColor(FundTheme.fg35)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if hits.isEmpty && !isSearching {
            VStack {
                Spacer().frame(height: 40)
                Text("未找到匹配的基金")
                    .font(.system(size: 12))
                    .foregroundColor(FundTheme.fg35)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(hits) { hit in
                        SearchRow(
                            hit: hit,
                            alreadyAdded: store.watchlist.contains(hit.code)
                        ) {
                            if !store.watchlist.contains(hit.code) {
                                store.watchlist.add(hit)
                                Task { await store.refreshNow() }
                                // Operation feedback so the user knows the
                                // tap landed — without this the only signal
                                // is the row's checkmark state flipping,
                                // which is easy to miss when scrolling.
                                ToastController.shared.success("已添加「\(hit.name)」到自选")
                            } else {
                                ToastController.shared.info("「\(hit.name)」已在自选中")
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func runSearch(_ q: String) async {
        guard !q.isEmpty else { hits = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            hits = try await FundClient.shared.search(q)
        } catch {
            hits = []
        }
    }
}

private struct SearchRow: View {
    let hit: FundSearchHit
    let alreadyAdded: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FundTheme.fgPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        tagChip(hit.displayTag, color: tagColor(hit.displayTag))
                        Text(hit.code)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(FundTheme.fg40)
                        if let cat = hit.category, cat != hit.displayTag {
                            Text(cat)
                                .font(.system(size: 10))
                                .foregroundColor(FundTheme.fg40)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                addBtn
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isHovered ? FundTheme.overlay04 : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .onHover { isHovered = $0 }
    }

    private var addBtn: some View {
        Group {
            if alreadyAdded {
                ZStack {
                    Circle()
                        .fill(FundTheme.overlay08)
                        .frame(width: 26, height: 26)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(FundTheme.downGreen)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(FundTheme.lime)
                        .frame(width: 26, height: 26)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                }
            }
        }
    }

    private func tagChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.18))
            )
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "ETF":   return Color(red: 0xFF/255, green: 0x8A/255, blue: 0x4C/255)
        case "指数":  return Color(red: 0x4C/255, green: 0xB6/255, blue: 0xFF/255)
        case "股票":  return Color(red: 0xA7/255, green: 0x85/255, blue: 0xFF/255)
        case "QDII":  return Color(red: 0xFF/255, green: 0xC4/255, blue: 0x54/255)
        case "混合":  return Color(red: 0x9A/255, green: 0xA0/255, blue: 0xA8/255)
        case "债券":  return Color(red: 0x2C/255, green: 0xD4/255, blue: 0x7E/255)
        case "货币":  return Color(red: 0x7A/255, green: 0xC0/255, blue: 0xC0/255)
        default:      return Color(red: 0x88/255, green: 0x88/255, blue: 0x88/255)
        }
    }
}
