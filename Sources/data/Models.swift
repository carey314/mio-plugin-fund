//
//  Models.swift
//  盯基金 plugin v0.2 (UI redesign per design spec)
//
//  Models grew from "watchlist with name+code" to "actual holding with
//  cost basis and shares" so the design's hero card (总市值 / 今日盈亏 /
//  累计盈亏) can compute real numbers. Cost/shares are optional — if
//  empty, the row falls back to "watchlist only" display (rate %
//  without ¥ amounts), so we don't force every user to type cost basis
//  on day one.
//

import Foundation

// MARK: - Fund

/// One fund the user has subscribed to (lives in the watchlist).
/// `shares` and `costNav` are optional: when set, the holdings hero
/// card shows real ¥ P&L; when nil, only the rate % displays.
struct WatchlistFund: Codable, Equatable, Identifiable {
    let code: String          // "005827"
    let name: String          // "易方达蓝筹精选混合"
    var addedAt: Date
    var displayOrder: Int

    /// Shares held (份额). Optional — nil means "I just want to watch this fund".
    var shares: Double?
    /// Average cost basis per share (持仓成本/单位净值).
    var costNav: Double?

    var id: String { code }

    /// True iff the user has filled in both shares + cost basis.
    var hasPosition: Bool {
        guard let s = shares, s > 0, let c = costNav, c > 0 else { return false }
        return true
    }

    /// Cost amount = shares × cost basis (only valid when hasPosition).
    var costAmount: Double? {
        guard let s = shares, let c = costNav else { return nil }
        return s * c
    }
}

/// Today's intraday estimate + last-published NAV for one fund.
/// Returned by `FundClient.estimate(for:)` (the
/// `fundgz.1234567.com.cn/js/{code}.js` JSONP feed).
struct FundEstimate: Equatable {
    let code: String
    let name: String
    let publishedDate: Date     // jzrq — date the published NAV applies to
    let publishedNav: Double    // dwjz — last published unit NAV
    let estimatedNav: Double?   // gsz — intraday estimated NAV (nil out of session)
    let estimatedRate: Double?  // gszzl — intraday %, e.g. 0.53 means +0.53%
    let estimatedAt: Date?      // gztime — last time estimate refreshed

    /// "Best available" NAV — use intraday estimate if we have it, else
    /// fall back to last published. The hero card uses this to compute
    /// market value during trade hours.
    var bestNav: Double { estimatedNav ?? publishedNav }
}

/// One row from the historical NAV table (used for sparkline).
struct FundNavPoint: Equatable {
    let date: Date
    let unitNav: Double
    let dailyRate: Double
}

/// One match from the eastmoney fund-suggest endpoint.
/// Includes "category" (fund type) and a heuristic "tag" for the
/// design's coloured chip.
struct FundSearchHit: Equatable, Identifiable {
    let code: String
    let name: String
    let category: String?       // e.g. "混合型-灵活" / "债券型-混合二级"
    var id: String { code }

    /// Coarse-grained tag derived from category for the design's coloured
    /// chip in the search list. Not authoritative — just hint colour.
    var displayTag: String {
        guard let c = category?.lowercased() else { return "基金" }
        if c.contains("指数") { return "指数" }
        if c.contains("股票") { return "股票" }
        if c.contains("混合") { return "混合" }
        if c.contains("债券") { return "债券" }
        if c.contains("货币") { return "货币" }
        if c.contains("qdii") { return "QDII" }
        if c.contains("etf") { return "ETF" }
        return "基金"
    }
}

// MARK: - Gold

/// Gold realtime quote. Same struct services SHFE 沪金 (RMB/g, used as
/// the chart price) and the foreign reference quotes (COMEX/London,
/// USD/oz with RMB/g conversion alongside).
struct GoldQuote: Equatable, Identifiable {
    enum Source: String, Codable, Hashable, CaseIterable {
        case shanghaiSpot = "shanghai_spot"
        case shfeFutures  = "shfe_futures"
        case comex        = "comex"
        case london       = "london"

        var displayName: String {
            switch self {
            case .shanghaiSpot: return "上海金"
            case .shfeFutures:  return "沪金"
            case .comex:        return "纽约金"
            case .london:       return "伦敦金"
            }
        }

        /// Sina symbol for `https://hq.sinajs.cn/list={symbol}`
        var sinaSymbol: String {
            switch self {
            case .shanghaiSpot: return "AU0"
            case .shfeFutures:  return "AU0"
            case .comex:        return "hf_GC"
            case .london:       return "hf_XAU"
            }
        }
    }

    let source: Source
    let last: Double
    /// Today's opening price. Distinct from `prevClose` — UI's "今开"
    /// row needs this, not yesterday's close.
    let open: Double?
    let prevClose: Double?
    let high: Double?
    let low: Double?
    let updatedAt: Date?
    /// Set when source ∈ {comex, london} so UI can show ¥/g alongside USD/oz.
    let rmbPerGram: Double?
    var id: String { source.rawValue }

    var change: Double? {
        guard let p = prevClose else { return nil }
        return last - p
    }
    var changeRate: Double? {
        guard let p = prevClose, p != 0 else { return nil }
        return (last - p) / p * 100.0
    }
}

/// One day's OHLCV for the gold K-line chart.
struct GoldDailyBar: Equatable {
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

/// User's gold holding position. Both fields optional so an empty
/// holding is valid (you might just want to watch the price without
/// committing). Persisted as JSON next to the watchlist.
struct GoldPosition: Codable, Equatable {
    /// Total grams held (克). Nil = no holding entered yet.
    var grams: Double?
    /// Average buy-in cost per gram (元/克).
    var costPerGram: Double?

    var hasPosition: Bool {
        guard let g = grams, g > 0, let c = costPerGram, c > 0 else { return false }
        return true
    }

    var costAmount: Double? {
        guard let g = grams, let c = costPerGram else { return nil }
        return g * c
    }
}

/// Time range for the gold chart tab strip (1月/3月/1年/全部).
enum GoldRange: String, CaseIterable, Identifiable {
    case oneMonth   = "1月"
    case threeMonth = "3月"
    case oneYear    = "1年"
    case all        = "全部"

    var id: String { rawValue }

    /// Number of days to slice from the daily history. `nil` = all.
    var days: Int? {
        switch self {
        case .oneMonth:   return 22       // ~22 trading days/month
        case .threeMonth: return 66
        case .oneYear:    return 250
        case .all:        return nil
        }
    }
}
