//
//  GoldClient.swift
//  盯基金 plugin
//
//  Realtime gold quotes from Sina Finance. One endpoint, four flavors.
//
//  Sina serves comma-separated field strings, NOT JSON. Encoding is
//  GB18030 for Chinese name fields, ASCII for numbers — see
//  SinaQuoteParser for details.
//

import Foundation

actor GoldClient {
    static let shared = GoldClient()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: One source

    func quote(for source: GoldQuote.Source) async throws -> GoldQuote {
        let symbol = source.sinaSymbol
        let url = URL(string: "https://hq.sinajs.cn/list=\(symbol)")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        // Sina enforces a Referer check on hq.sinajs.cn endpoints —
        // requests without a finance.sina.com.cn referer return empty
        // payloads. Documented hack but it has held since 2016.
        req.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")

        let (data, _) = try await session.data(for: req)
        guard let q = SinaQuoteParser.parse(data: data, source: source) else {
            throw FundClientError.malformed("sina parse failed for \(symbol)")
        }
        return q
    }

    // MARK: Bulk

    /// Fetch all four sources in parallel. Failures degrade silently
    /// so off-hours empty payloads don't sink the panel.
    func quoteAll() async -> [GoldQuote] {
        await withTaskGroup(of: GoldQuote?.self) { group in
            for src in [GoldQuote.Source.comex, .london, .shfeFutures] {
                group.addTask { try? await self.quote(for: src) }
            }
            var out: [GoldQuote] = []
            for await q in group { if let q { out.append(q) } }
            return out
        }
    }
}
