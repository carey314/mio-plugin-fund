//
//  FundStore.swift
//  盯基金 plugin v0.2
//
//  Glue between watchlist + clients + UI. Now also caches gold daily
//  K-line so the chart can switch ranges (1月/3月/1年/全部) without
//  re-fetching.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class FundStore: ObservableObject {
    static let shared = FundStore()

    @Published private(set) var estimates: [String: FundEstimate] = [:]
    @Published private(set) var goldQuotes: [GoldQuote.Source: GoldQuote] = [:]
    @Published private(set) var goldDailyBars: [GoldDailyBar] = []
    /// Spot gold (AU9999) — what Alipay shows on 「国内金价」 tab.
    @Published private(set) var spotGold: SpotGoldQuote?
    /// Today's intraday minute line for AU0 — replaces daily K-line in chart.
    @Published private(set) var goldMinuteLine: [GoldMinutePoint] = []
    @Published private(set) var lastFundRefresh: Date?
    @Published private(set) var lastGoldRefresh: Date?
    @Published private(set) var lastGoldHistRefresh: Date?
    @Published private(set) var isRefreshing = false

    let watchlist: Watchlist
    let goldPosition: GoldPositionStore
    private let scheduler = RefreshScheduler()
    private var fundTask: Task<Void, Never>?
    private var goldTask: Task<Void, Never>?

    init() {
        self.watchlist = Watchlist()
        self.goldPosition = GoldPositionStore()
    }

    // MARK: - Lifecycle

    func start() {
        guard fundTask == nil else { return }
        fundTask = Task { [weak self] in await self?.fundLoop() }
        goldTask = Task { [weak self] in await self?.goldLoop() }

        // K-line history is rarely refreshed — once on start, then once
        // every hour (price moved enough to redraw the bottom of the chart).
        Task { [weak self] in await self?.refreshGoldKLine() }
    }

    func stop() {
        fundTask?.cancel(); fundTask = nil
        goldTask?.cancel(); goldTask = nil
    }

    // MARK: - Manual triggers

    func refreshNow() async {
        await refreshFunds()
        await refreshGold()
        await refreshGoldKLine()
    }

    // MARK: - Fund refresh

    private func fundLoop() async {
        await refreshFunds()
        while !Task.isCancelled {
            let interval = scheduler.interval(for: .fundsActive)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { break }
            await refreshFunds()
        }
    }

    private func refreshFunds() async {
        let codes = watchlist.codes
        guard !codes.isEmpty else { return }
        isRefreshing = true

        // Split codes by venue: ETFs (场内 — Shanghai/Shenzhen exchange)
        // get the stock-like Sina endpoint, mutual funds (场外) get the
        // Tiantian estimation feed. Same FundEstimate output shape so the
        // UI doesn't care which venue a row came from.
        let etfCodes = codes.filter { ETFClient.isETFCode($0) }
        let otcCodes = codes.filter { !ETFClient.isETFCode($0) }
        FundDebugLog.write("refreshFunds start codes=\(codes) etf=\(etfCodes) otc=\(otcCodes)")

        async let otcResults: [FundEstimate] = FundClient.shared.estimates(for: otcCodes)
        async let etfQuotes: [ETFQuote] = ETFClient.shared.quotes(for: etfCodes)

        var dict = self.estimates
        let otc = await otcResults
        let etf = await etfQuotes
        FundDebugLog.write("refreshFunds got otc=\(otc.count)/\(otcCodes.count) etf=\(etf.count)/\(etfCodes.count)")
        for r in otc { dict[r.code] = r }
        for q in etf {
            // Map ETFQuote → FundEstimate so UI is uniform. published =
            // prevClose, intraday = current price, rate = day change %.
            dict[q.code] = FundEstimate(
                code: q.code,
                name: q.name,
                publishedDate: q.updatedAt ?? Date(),
                publishedNav: q.prevClose,
                estimatedNav: q.last,
                estimatedRate: q.changeRate,
                estimatedAt: q.updatedAt
            )
        }
        self.estimates = dict
        self.lastFundRefresh = Date()
        isRefreshing = false
    }

    // MARK: - Gold realtime

    private func goldLoop() async {
        await refreshGold()
        while !Task.isCancelled {
            let interval = scheduler.interval(for: .gold)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { break }
            await refreshGold()
        }
    }

    private func refreshGold() async {
        // Three things in parallel: legacy realtime (London/NY/SHFE),
        // AU9999 spot, and the minute line. None block the others —
        // each falls back silently on failure.
        async let realtime: [GoldQuote] = GoldClient.shared.quoteAll()
        async let spot: SpotGoldQuote? = try? SpotGoldClient.shared.quote()
        async let minute: [GoldMinutePoint] = (try? await GoldMinuteClient.shared.minuteLine()) ?? []

        var dict = self.goldQuotes
        for q in await realtime { dict[q.source] = q }
        self.goldQuotes = dict
        if let s = await spot { self.spotGold = s }
        let m = await minute
        if !m.isEmpty { self.goldMinuteLine = m }
        self.lastGoldRefresh = Date()
    }

    // MARK: - Gold K-line history

    private func refreshGoldKLine() async {
        do {
            let bars = try await GoldKlineClient.shared.dailyKLine(symbol: "AU0")
            self.goldDailyBars = bars
            self.lastGoldHistRefresh = Date()
        } catch {
            NSLog("[fund-plugin] gold kline fetch failed: \(error)")
        }
    }

    /// Slice the loaded K-line for a given range. Returns the most
    /// recent N bars (or all if range == .all).
    func goldBars(for range: GoldRange) -> [GoldDailyBar] {
        guard let n = range.days else { return goldDailyBars }
        return Array(goldDailyBars.suffix(n))
    }

    // MARK: - Aggregate computed for hero card

    /// Total market value across all watchlist funds that have a
    /// position (shares + costNav set). Returns nil when no positions.
    var totalMarketValue: Double? {
        var total: Double = 0
        var any = false
        for f in watchlist.funds {
            guard let shares = f.shares, shares > 0 else { continue }
            let nav = estimates[f.code]?.bestNav
            guard let n = nav else { continue }
            total += shares * n
            any = true
        }
        return any ? total : nil
    }

    /// Total cost basis (Σ shares × costNav) across positions. Nil if none.
    var totalCost: Double? {
        var total: Double = 0
        var any = false
        for f in watchlist.funds {
            guard let cost = f.costAmount else { continue }
            total += cost
            any = true
        }
        return any ? total : nil
    }

    /// Sum of today's ¥ P&L across funds with positions.
    /// Today's ¥ delta on one fund = shares × bestNav × (estimatedRate / (100 + estimatedRate))
    /// We approximate with: shares × (bestNav - publishedNav).
    var totalDayPnL: Double? {
        var total: Double = 0
        var any = false
        for f in watchlist.funds {
            guard let shares = f.shares, shares > 0 else { continue }
            guard let est = estimates[f.code] else { continue }
            // Day ¥ = shares × (intraday nav - last published nav)
            let estNav = est.estimatedNav ?? est.publishedNav
            let delta = (estNav - est.publishedNav) * shares
            total += delta
            any = true
        }
        return any ? total : nil
    }
}
