//
//  RefreshScheduler.swift
//  盯基金 plugin
//
//  Drives the refresh cadence based on what's tradeable right now.
//  Different things have different refresh budgets:
//
//    Tradeable now            Cadence
//    ─────────────────────────────────
//    A-share funds (intraday)  60 s   (estimate API is ~1 min granularity)
//    A-share funds (closed)    30 min (just to pick up newly published NAV)
//    Foreign gold (24/5)       30 s   (Sina updates GC/XAU continuously)
//    Domestic gold             30 s   while SHFE open
//
//  Trade hours (Asia/Shanghai):
//    A-share:        09:30–11:30, 13:00–15:00, Mon–Fri
//    SHFE day:       09:00–10:15, 10:30–11:30, 13:30–15:00
//    SHFE night:     21:00–02:30
//    COMEX gold:     06:00–05:00 next day (essentially 23h, 5 days/week)
//    LBMA London:    rolls with COMEX in practice
//

import Foundation

@MainActor
final class RefreshScheduler {

    enum Tier {
        /// Funds intraday cadence.
        case fundsActive
        /// Funds idle cadence — only listening for end-of-day NAV publish.
        case fundsIdle
        /// Realtime gold tier (always on, foreign markets virtually 24/7).
        case gold
    }

    /// Returns refresh interval (seconds) for a tier at the given moment.
    func interval(for tier: Tier, at now: Date = Date()) -> TimeInterval {
        switch tier {
        case .fundsActive:
            return isAShareTradeHour(now) ? 60 : 30 * 60
        case .fundsIdle:
            return 30 * 60
        case .gold:
            // Always 30s — foreign gold trades virtually 24/7. SHFE has
            // closed windows but we don't bother backing off; the request
            // is cheap and Sina caches the latest tick anyway.
            return 30
        }
    }

    /// True iff `now` falls inside an A-share trading session
    /// (09:30–11:30, 13:00–15:00 China time, Mon–Fri, no holiday awareness yet).
    func isAShareTradeHour(_ now: Date = Date()) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let weekday = cal.component(.weekday, from: now) // 1=Sun … 7=Sat
        guard (2...6).contains(weekday) else { return false }
        let hm = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        // 09:30–11:30
        if hm >= 9 * 60 + 30 && hm < 11 * 60 + 30 { return true }
        // 13:00–15:00
        if hm >= 13 * 60 && hm < 15 * 60 { return true }
        return false
    }

    /// True iff SHFE gold is in a trading window (loose — no holiday).
    func isSHFETradeHour(_ now: Date = Date()) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let weekday = cal.component(.weekday, from: now)
        // Day session also runs Mon-Fri; night session technically can
        // span into Sat early morning but we keep it simple.
        guard (2...6).contains(weekday) else { return false }
        let hm = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        // 09:00-10:15
        if hm >= 9 * 60 && hm < 10 * 60 + 15 { return true }
        // 10:30-11:30
        if hm >= 10 * 60 + 30 && hm < 11 * 60 + 30 { return true }
        // 13:30-15:00
        if hm >= 13 * 60 + 30 && hm < 15 * 60 { return true }
        // 21:00-23:59 + 00:00-02:30
        if hm >= 21 * 60 { return true }
        if hm < 2 * 60 + 30 { return true }
        return false
    }
}
