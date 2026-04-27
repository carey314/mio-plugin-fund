//
//  SpotGoldClient.swift
//  看盘侠 plugin v0.3
//
//  上海金现货 AU9999 (SGE) realtime — same data Alipay shows on the
//  「国内金价」 tab. Distinct from the SHFE futures AU0 we already pull:
//  AU9999 is the SGE physical-spot reference price retail jewellery
//  banks quote off, whereas AU0 is the futures contract.
//
//  Endpoint: `https://hq.sinajs.cn/list=gds_AU9999`
//
//  Field layout (verified 2026-04-26):
//    [0]  current price        1040.00
//    [1]  ?                     0
//    [2]  ?                     1039.00     (looks like avg or bid?)
//    [3]  ?                     1049.00
//    [4]  high                  1044.00
//    [5]  low                   1034.00
//    [6]  time                  "02:30:00"
//    [7]  prevClose             1033.25
//    [8]  open                  1039.90
//    [9]  volume                3136
//    [10] (purity?)             100.00
//    [11] (purity?)             100.00
//    [12] date                  "2026-04-25"
//    [13] name (GBK)            "黄金99"
//

import Foundation

/// Spot gold quote (SGE AU9999 / AU99.99).
struct SpotGoldQuote: Equatable {
    let last: Double          // current
    let prevClose: Double     // 昨收
    let open: Double          // 今开
    let high: Double          // 最高
    let low: Double           // 最低
    let updatedAt: Date?
    let name: String          // "黄金99"

    var change: Double { last - prevClose }
    var changeRate: Double { prevClose == 0 ? 0 : change / prevClose * 100 }
}

actor SpotGoldClient {
    static let shared = SpotGoldClient()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    /// Fetch the current AU9999 spot quote.
    func quote() async throws -> SpotGoldQuote {
        let url = URL(string: "https://hq.sinajs.cn/list=gds_AU9999")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")

        let (data, _) = try await session.data(for: req)
        // Sina serves GB18030 here too (name field is Chinese).
        let gbEnc = String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let s = String(data: data, encoding: gbEnc)
            ?? String(data: data, encoding: .utf8)
            ?? ""

        guard let lQ = s.firstIndex(of: "\""),
              let rQ = s[s.index(after: lQ)...].firstIndex(of: "\"") else {
            throw FundClientError.malformed("AU9999 payload parse")
        }
        let body = String(s[s.index(after: lQ)..<rQ])
        let fields = body.components(separatedBy: ",")
        // Off-hours can return an empty payload; guard.
        guard fields.count >= 13,
              let last = Double(fields[0]),
              let high = Double(fields[4]),
              let low = Double(fields[5]),
              let prevClose = Double(fields[7]),
              let open = Double(fields[8]) else {
            throw FundClientError.malformed("AU9999 field decode (\(fields.count) fields)")
        }
        let timeStr = fields[6]
        let dateStr = fields[12]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let updatedAt = fmt.date(from: "\(dateStr) \(timeStr)")
        let name = fields.count > 13 ? fields[13] : "上海金"

        return SpotGoldQuote(
            last: last, prevClose: prevClose, open: open,
            high: high, low: low, updatedAt: updatedAt, name: name
        )
    }
}
