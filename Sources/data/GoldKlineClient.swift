//
//  GoldKlineClient.swift
//  盯基金 plugin v0.2
//
//  Daily K-line history for the gold chart. Uses Sina's classic
//  inner-futures endpoint:
//
//    https://stock2.finance.sina.com.cn/futures/api/json.php/IndexService.getInnerFuturesDailyKLine?symbol=AU0
//
//  Returns a JSON array of arrays:
//    [[date, open, high, low, close, volume], ...]
//
//  Stable since 2008, used by every futures-tracker website in China.
//  Falls back gracefully if the endpoint format ever changes — we
//  parse defensively.
//

import Foundation

actor GoldKlineClient {
    static let shared = GoldKlineClient()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    /// Fetch the full daily K-line for the given symbol (default AU0
    /// = SHFE 沪金主连). Returns oldest → newest.
    func dailyKLine(symbol: String = "AU0") async throws -> [GoldDailyBar] {
        let url = URL(string:
            "https://stock2.finance.sina.com.cn/futures/api/json.php/IndexService.getInnerFuturesDailyKLine?symbol=\(symbol)"
        )!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")

        let (data, _) = try await session.data(for: req)

        // Sina returns: [["2008-01-09","230.950","230.990","221.880","223.300","103364"], ...]
        // Strings only — we parse to Double.
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String]] else {
            throw FundClientError.malformed("kline array decode failed")
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        fmt.dateFormat = "yyyy-MM-dd"

        return arr.compactMap { row -> GoldDailyBar? in
            guard row.count >= 5,
                  let date = fmt.date(from: row[0]),
                  let open = Double(row[1]),
                  let high = Double(row[2]),
                  let low  = Double(row[3]),
                  let close = Double(row[4]) else { return nil }
            let volume = row.count >= 6 ? (Double(row[5]) ?? 0) : 0
            return GoldDailyBar(date: date, open: open, high: high, low: low, close: close, volume: volume)
        }
    }

    /// Convenience: slice the most recent N days.
    func recentDailyKLine(days: Int?, symbol: String = "AU0") async throws -> [GoldDailyBar] {
        let full = try await dailyKLine(symbol: symbol)
        guard let n = days, n < full.count else { return full }
        return Array(full.suffix(n))
    }
}
