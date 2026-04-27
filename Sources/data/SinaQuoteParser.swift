//
//  SinaQuoteParser.swift
//  盯基金 plugin
//
//  Parses Sina Finance's classic JS-string quote format. Every realtime
//  endpoint of the form `https://hq.sinajs.cn/list=XXX` returns the same
//  shape:
//
//      var hq_str_XXX="field1,field2,field3,...";
//
//  Field positions are domain-dependent. We only decode the four flavors
//  this plugin uses (hf_* foreign futures and AU* domestic futures).
//
//  GBK is the encoding for the Chinese name fields. We don't care about
//  those — we only need the numeric fields, which are pure ASCII and
//  parse fine even when the rest of the string is garbled bytes.
//

import Foundation

enum SinaQuoteParser {

    /// Parse a Sina quote response into a single GoldQuote.
    /// Returns nil if the data is empty (Sina returns a one-byte
    /// `""` payload for unknown symbols).
    static func parse(rawString: String, source: GoldQuote.Source) -> GoldQuote? {
        // Find the first `="` ... `";` payload.
        guard let eq = rawString.firstIndex(of: "="),
              let firstQuote = rawString[eq...].firstIndex(of: "\"") else {
            return nil
        }
        let afterQuote = rawString.index(after: firstQuote)
        guard let lastQuote = rawString[afterQuote...].lastIndex(of: "\"") else {
            return nil
        }
        let body = String(rawString[afterQuote..<lastQuote])
        guard !body.isEmpty else { return nil }
        let fields = body.components(separatedBy: ",")

        switch source {
        case .comex, .london:
            return parseForeignFutures(fields: fields, source: source)
        case .shfeFutures, .shanghaiSpot:
            return parseDomesticFutures(fields: fields, source: source)
        }
    }

    /// Parse a Sina quote response from raw `Data` (handles encoding).
    /// We force decode with UTF-8 first; if that fails (Chinese name
    /// fields use GBK), fall back to GBK. Numeric fields parse the
    /// same either way.
    static func parse(data: Data, source: GoldQuote.Source) -> GoldQuote? {
        if let s = String(data: data, encoding: .utf8) {
            return parse(rawString: s, source: source)
        }
        // Chinese encodings — Sina uses GB18030 (superset of GBK).
        let cfStr = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let nsEnc = String.Encoding(rawValue: cfStr)
        if let s = String(data: data, encoding: nsEnc) {
            return parse(rawString: s, source: source)
        }
        // Last resort: ASCII with lossy conversion. Numeric fields survive.
        let lossy = String(data: data, encoding: .ascii) ?? ""
        return parse(rawString: lossy, source: source)
    }

    // MARK: - Foreign futures (hf_*)
    //
    // Verified field layout (from `https://hq.sinajs.cn/list=hf_GC` on
    // 2026-04-25 nightly run — see test-final.py output):
    //
    //   [0] last (latest)             4728.253
    //   [1] (empty / bid sometimes)
    //   [2] open                      4725.100
    //   [3] high                      4725.300   ← bug-prone: actually high
    //   [4] day high                  4757.100
    //   [5] day low                   4672.200
    //   [6] update time               "04:59:58"
    //   [7] prev settle               4724.000
    //   [8] prev close                4715.600
    //   [9-11] zeros / volume / position
    //   [12] date                     "2026-04-25"
    //   [13] name (GBK garbled here)
    //
    // We only need: last, day high, day low, prev close, update time, date.
    private static func parseForeignFutures(fields: [String], source: GoldQuote.Source) -> GoldQuote? {
        guard fields.count >= 13 else { return nil }
        guard let last = Double(fields[0]) else { return nil }
        let high = Double(fields[4])
        let low  = Double(fields[5])
        let prevClose = Double(fields[8]).nonZero
        let timeStr = fields[6]
        let dateStr = fields[12]
        let updatedAt = combineForeign(date: dateStr, time: timeStr)

        // hf_GC / hf_XAU return USD/oz. RMB conversion is NOT included
        // in the raw feed (akshare adds it on the Python side using a
        // separate FX call). We compute it here only when the realtime
        // USD/CNY rate is available — for v0.1 we punt and let the UI
        // call FxClient if needed.
        let open = Double(fields[2])
        return GoldQuote(
            source: source, last: last,
            open: open, prevClose: prevClose, high: high, low: low,
            updatedAt: updatedAt, rmbPerGram: nil
        )
    }

    // MARK: - Domestic futures (AU0 etc.)
    //
    // Verified field layout from `https://hq.sinajs.cn/list=AU0` (2026-04-25):
    //
    //   [0] name (GBK)
    //   [1] (volume of last tick)     145957
    //   [2] open                      574.86
    //   [3] high                      585.84
    //   [4] low                       574.40
    //   [5] last                      574.94
    //   [6] bid1                      581.58
    //   [7] ask1                      581.60
    //   [8] last_settle?              581.56
    //   [9] reserved                  0.00
    //   [10] prev close              572.76
    //   [13] volume                  189097
    //   [14] open interest           308940
    //   [17] date                    "2024-07-17"  ← stale on this snapshot, normal off-hours
    //
    // Domestic AU is RMB/g — we set rmbPerGram = last directly.
    private static func parseDomesticFutures(fields: [String], source: GoldQuote.Source) -> GoldQuote? {
        guard fields.count >= 11 else { return nil }
        guard let last = Double(fields[5]), last > 0 else { return nil }
        let high = Double(fields[3])
        let low  = Double(fields[4])
        let prevClose = Double(fields[10]).nonZero

        // Sina exposes a settled date but not a precise time stamp
        // for AU realtime. Use the trade date + current wall time
        // when fields[17] is available; otherwise leave nil.
        let dateStr = fields.count > 17 ? fields[17] : ""
        let updatedAt = combineDomestic(date: dateStr)
        let open = Double(fields[2])

        return GoldQuote(
            source: source, last: last,
            open: open, prevClose: prevClose, high: high, low: low,
            updatedAt: updatedAt, rmbPerGram: last
        )
    }

    // MARK: - Date helpers

    /// Foreign futures format "2026-04-25" + "04:59:58" → Date in
    /// America/New_York-equivalent rendered in CN time zone for display.
    private static func combineForeign(date: String, time: String) -> Date? {
        guard !date.isEmpty, !time.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // Sina serves the NY/London exchange wall time as-is; we tag
        // it with Asia/Shanghai so it lines up with the Mac's local
        // clock for "时间感". Investors care more about elapsed-time
        // freshness than which time zone the exchange ran in.
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: "\(date) \(time)")
    }

    private static func combineDomestic(date: String) -> Date? {
        guard !date.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date)
    }
}

private extension Optional where Wrapped == Double {
    /// Sina sometimes encodes "no prev close" as 0. Drop that to nil
    /// so downstream code doesn't compute a +∞ percent change.
    var nonZero: Double? {
        if case .some(let v) = self, v > 0 { return v }
        return nil
    }
}
