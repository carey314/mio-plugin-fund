//
//  EtfClient.swift
//  看盘侠 plugin v0.3
//
//  Realtime quotes for exchange-traded funds (场内 ETF). Different
//  endpoint from open-end mutual funds — ETFs trade on Shanghai/Shenzhen
//  exchanges with stock-like tick data.
//
//  Endpoint: `https://hq.sinajs.cn/list={prefix}{code}` where prefix is
//  "sh" (上交所) or "sz" (深交所), encoded GB18030. Same family as the
//  gold AU0 endpoint we already use, just stock-format payload instead
//  of futures.
//
//  Field layout (verified 2026-04-26 with sz159206 卫星 ETF):
//    [0]  name (GBK)             "卫星ETF"
//    [1]  prevClose (昨收)        1.854
//    [2]  open (今开)             1.867
//    [3]  current (现价)          1.806
//    [4]  high (最高)             1.857
//    [5]  low  (最低)             1.801
//    [6]  bid1 (买一价)           1.806
//    [7]  ask1 (卖一价)           1.807
//    [8]  volume (成交量·股)      902910170
//    [9]  turnover (成交额·元)    1643683554.028
//    [10..29] 五档买卖盘
//    [30] date "2026-04-24"
//    [31] time "15:00:00"
//

import Foundation

/// Minimal subset of the Sina stock payload we surface in the UI.
struct ETFQuote: Equatable {
    let code: String          // raw 6-digit code (no prefix)
    let name: String
    let prevClose: Double
    let open: Double
    let last: Double
    let high: Double
    let low: Double
    let updatedAt: Date?

    var change: Double { last - prevClose }
    var changeRate: Double { prevClose == 0 ? 0 : change / prevClose * 100 }
}

actor ETFClient {
    static let shared = ETFClient()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    /// True iff this looks like a tradeable ETF code (Shanghai or Shenzhen).
    /// Routing rules taken from CSRC code blocks (3-digit prefix of the
    /// 6-digit ticker):
    ///   - 51x, 52x, 56x, 58x → Shanghai ETFs (sh prefix)
    ///   - 15x, 16x, 18x → Shenzhen ETFs (sz prefix)
    /// Anything else falls back to open-end mutual fund routing.
    /// 6-digit ticker / 1000 = leading 3 digits — earlier code mistakenly
    /// used /10000 which always returned the leading 2 digits and made
    /// every ETF look like an OTC fund.
    static func isETFCode(_ code: String) -> Bool {
        guard code.count == 6, let n = Int(code) else { return false }
        let prefix = n / 1000
        // P0 fix (2026-05-19 review): the prior `150...199` range was
        // too wide — it caught LOF codes that aren't ETFs:
        //   161xxx 兴全 LOF / 162xxx 黄金 LOF / 163xxx 招商 LOF
        //   165xxx 银华 LOF / 166xxx 中欧 LOF / 167xxx 中海 LOF
        //   168xxx, 169xxx 多家 LOF
        // LOFs trade by 1-day NAV pricing, not by ETF intraday quote
        // ticks. Routing them through ETFClient would surface stale
        // or wrong-shaped data on the holding row.
        // Explicit-deny the LOF prefixes; keep everything else in the
        // legacy range routing for backwards compat.
        switch prefix {
        case 161, 162, 163, 165, 166, 167, 168, 169:
            return false
        case 510...599, 150...199:
            return true
        default:
            return false
        }
    }

    /// Returns "sh" or "sz" for the given ETF code, or nil if it isn't an ETF.
    static func sinaPrefix(for code: String) -> String? {
        guard code.count == 6, let n = Int(code) else { return nil }
        let prefix = n / 1000
        if (510...599).contains(prefix) { return "sh" }
        if (150...199).contains(prefix) { return "sz" }
        return nil
    }

    func quote(for code: String) async throws -> ETFQuote {
        guard let prefix = Self.sinaPrefix(for: code) else {
            throw FundClientError.malformed("\(code) is not an ETF code")
        }
        let url = URL(string: "https://hq.sinajs.cn/list=\(prefix)\(code)")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")

        let (data, _) = try await session.data(for: req)

        // Sina serves GB18030 so the Chinese name field decodes cleanly.
        let gbEnc = String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let s = String(data: data, encoding: gbEnc) ?? String(data: data, encoding: .utf8),
              let lQ = s.firstIndex(of: "\""),
              let rQ = s[s.index(after: lQ)...].firstIndex(of: "\"") else {
            throw FundClientError.malformed("etf payload parse failed for \(code)")
        }
        let body = String(s[s.index(after: lQ)..<rQ])
        let fields = body.components(separatedBy: ",")
        guard fields.count >= 30 else {
            throw FundClientError.malformed("etf field count \(fields.count) for \(code)")
        }
        guard let prevClose = Double(fields[1]),
              let open = Double(fields[2]),
              let last = Double(fields[3]),
              let high = Double(fields[4]),
              let low = Double(fields[5]) else {
            throw FundClientError.malformed("etf number parse failed for \(code)")
        }

        let dateStr = fields.count > 30 ? fields[30] : ""
        let timeStr = fields.count > 31 ? fields[31] : ""
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let updatedAt = fmt.date(from: "\(dateStr) \(timeStr)")

        return ETFQuote(
            code: code, name: fields[0],
            prevClose: prevClose, open: open, last: last,
            high: high, low: low, updatedAt: updatedAt
        )
    }

    /// Fetch many ETF quotes in parallel; logs per-code failures so
    /// silent breakage in production is debuggable.
    func quotes(for codes: [String]) async -> [ETFQuote] {
        await withTaskGroup(of: ETFQuote?.self) { group in
            for c in codes {
                group.addTask {
                    do { return try await self.quote(for: c) }
                    catch {
                        FundDebugLog.write("ETF quote \(c) failed: \(error)")
                        return nil
                    }
                }
            }
            var out: [ETFQuote] = []
            for await q in group { if let q { out.append(q) } }
            return out
        }
    }
}
