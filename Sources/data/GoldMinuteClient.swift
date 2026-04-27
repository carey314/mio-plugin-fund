//
//  GoldMinuteClient.swift
//  看盘侠 plugin v0.3
//
//  Realtime minute-line for SHFE 沪金 AU0 — replaces the daily K-line
//  in the chart widget. This matches what Alipay / 同花顺 show in the
//  "国内金价" panel: an intraday tick line spanning
//  20:00 → 02:30 (night session) → 09:00 → 15:30 (day session).
//
//  Endpoint: Sina futures inner getMinLine
//    https://stock.finance.sina.com.cn/futures/api/jsonp.php
//      /var-_t=/InnerFuturesNewService.getMinLine?symbol=AU0
//
//  Returns JSONP: `var-_t=([[time, last, avgPrice, vol, oi, prevClose, date], ...]);`
//  First row carries the prevClose + date; subsequent rows are tick samples.
//

import Foundation

/// One minute sample from the AU0 intraday line.
struct GoldMinutePoint: Equatable {
    /// Trading time, formatted "HH:mm" (e.g. "21:00").
    let time: String
    /// Last traded price (RMB/g).
    let price: Double
    /// Cumulative volume up to this minute.
    let volume: Double
}

actor GoldMinuteClient {
    static let shared = GoldMinuteClient()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    /// Fetch today's minute line for the given futures symbol (default
    /// AU0 = SHFE 沪金主连). Returns oldest → newest.
    func minuteLine(symbol: String = "AU0") async throws -> [GoldMinutePoint] {
        let url = URL(string:
            "https://stock.finance.sina.com.cn/futures/api/jsonp.php/var-_t=/InnerFuturesNewService.getMinLine?symbol=\(symbol)"
        )!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")

        let (data, _) = try await session.data(for: req)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw FundClientError.malformed("minline non-utf8")
        }

        // Strip JSONP wrapper: `var-_t=(<json>);` (Sina injects a redirect
        // script first; ignore that and keep the part starting at `var-_t=(`).
        guard let lParen = raw.range(of: "var-_t=(")?.upperBound,
              let rParen = raw[lParen...].lastIndex(of: ")") else {
            throw FundClientError.malformed("minline jsonp wrapper missing")
        }
        let inner = String(raw[lParen..<rParen])

        // Empty payload (off-hours / no session yet today) is `null`.
        if inner.trimmingCharacters(in: .whitespaces) == "null" { return [] }

        guard let innerData = inner.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: innerData) as? [[Any]] else {
            throw FundClientError.malformed("minline array decode")
        }

        return arr.compactMap { row -> GoldMinutePoint? in
            // Layout: [time, last, avgPrice, volume, openInterest, prevClose?, date?]
            guard row.count >= 4 else { return nil }
            // Sina returns numbers as strings inside the array — coerce.
            let timeStr = row[0] as? String ?? ""
            let priceStr = row[1] as? String ?? ""
            let volStr = row[3] as? String ?? "0"
            guard let p = Double(priceStr), p > 0 else { return nil }
            return GoldMinutePoint(time: timeStr, price: p, volume: Double(volStr) ?? 0)
        }
    }
}
