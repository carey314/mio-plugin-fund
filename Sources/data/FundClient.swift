//
//  FundClient.swift
//  盯基金 plugin
//
//  HTTP client for fund data. Three endpoints, all 10+ years old,
//  used by every Chinese fintech app. No Python dependency.
//
//  Endpoints:
//    1. Search:    https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx
//                  (Eastmoney — JSON)
//    2. Estimate:  http://fundgz.1234567.com.cn/js/{code}.js
//                  (TianTian — JSONP `jsonpgz({...})`)
//    3. History:   https://api.fund.eastmoney.com/f10/lsjz?fundCode={code}&pageSize=N
//                  (Eastmoney F10 — JSON, requires Referer header)
//

import Foundation

enum FundClientError: Error, LocalizedError {
    case badStatus(Int)
    case malformed(String)
    case decode(Error)
    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .malformed(let msg):  return "Malformed response: \(msg)"
        case .decode(let err):     return "Decode failed: \(err.localizedDescription)"
        }
    }
}

actor FundClient {
    static let shared = FundClient()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        // 8s wasn't enough on cold start — TLS handshake to
        // fundgz.1234567.com.cn often took 7-10s after app launch and
        // tripped the request timeout. 15s gives the first request
        // headroom; subsequent reuses are sub-second.
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 25
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: 1. Search

    /// Fuzzy search for funds by name, code, or pinyin abbreviation.
    /// Returns up to 10 hits.
    func search(_ query: String) async throws -> [FundSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let url = URL(string: "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=1&key=\(encoded)")!
        let (data, resp) = try await session.data(from: url)
        try Self.assertOK(resp)

        struct Envelope: Decodable {
            let ErrCode: Int
            let Datas: [Hit]
        }
        struct Hit: Decodable {
            let CODE: String
            let NAME: String
            let CATEGORYDESC: String?
        }
        do {
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            return env.Datas.prefix(10).map {
                FundSearchHit(code: $0.CODE, name: $0.NAME, category: $0.CATEGORYDESC)
            }
        } catch {
            throw FundClientError.decode(error)
        }
    }

    // MARK: 2. Intraday estimate

    /// Fetch the live intraday estimate for one fund.
    ///
    /// Endpoint returns JSONP wrapped in `jsonpgz(...)`. Out-of-session
    /// (weekends, after-hours), `gsz` / `gszzl` / `gztime` may be empty
    /// strings — we return nil for those fields rather than fake them.
    func estimate(for code: String) async throws -> FundEstimate {
        guard !code.isEmpty else { throw FundClientError.malformed("empty code") }
        // Cache-buster — Tiantian aggressively caches; without `_=ts`
        // we can be served a 5-minute-old snapshot.
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        // HTTPS — Tiantian also serves over TLS, and Mio's host ATS
        // policy may block plain HTTP, which would silently kill OTC
        // fund estimates without surfacing in the UI.
        let url = URL(string: "https://fundgz.1234567.com.cn/js/\(code).js?rt=\(ts)")!

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, resp) = try await session.data(for: req)
        try Self.assertOK(resp)

        guard let raw = String(data: data, encoding: .utf8) else {
            throw FundClientError.malformed("non-utf8")
        }
        // Strip JSONP wrapper: jsonpgz({...});
        guard let lParen = raw.firstIndex(of: "("),
              let rParen = raw.lastIndex(of: ")") else {
            // Tiantian returns `jsonpgz();` (empty) for codes that don't
            // exist or aren't yet tradeable — surface that distinctly.
            if raw.contains("jsonpgz();") {
                throw FundClientError.malformed("fund not found: \(code)")
            }
            throw FundClientError.malformed("missing JSONP parens")
        }
        let inner = raw[raw.index(after: lParen)..<rParen]
        guard let innerData = String(inner).data(using: .utf8) else {
            throw FundClientError.malformed("inner non-utf8")
        }

        struct Raw: Decodable {
            let fundcode: String
            let name: String
            let jzrq: String   // "2026-04-23"
            let dwjz: String
            let gsz: String?
            let gszzl: String?
            let gztime: String? // "2026-04-24 15:00"
        }
        let r: Raw
        do { r = try JSONDecoder().decode(Raw.self, from: innerData) }
        catch { throw FundClientError.decode(error) }

        let dateFmt = DateFormatter.fundDate
        let timeFmt = DateFormatter.fundDateTime
        guard let pubDate = dateFmt.date(from: r.jzrq),
              let pubNav = Double(r.dwjz) else {
            throw FundClientError.malformed("unparseable published nav")
        }
        let estNav = r.gsz.flatMap { Double($0) }
        let estRate = r.gszzl.flatMap { Double($0) }
        let estAt = r.gztime.flatMap { timeFmt.date(from: $0) }

        return FundEstimate(
            code: r.fundcode, name: r.name,
            publishedDate: pubDate, publishedNav: pubNav,
            estimatedNav: estNav, estimatedRate: estRate,
            estimatedAt: estAt
        )
    }

    /// Convenience: fetch many estimates in parallel. Failures for
    /// individual codes are swallowed (returned as missing entries) so
    /// one dead code doesn't sink the whole refresh.
    func estimates(for codes: [String]) async -> [FundEstimate] {
        await withTaskGroup(of: FundEstimate?.self) { group in
            for c in codes {
                group.addTask {
                    do { return try await self.estimate(for: c) }
                    catch {
                        FundDebugLog.write("OTC estimate \(c) failed: \(error)")
                        return nil
                    }
                }
            }
            var out: [FundEstimate] = []
            out.reserveCapacity(codes.count)
            for await result in group {
                if let r = result { out.append(r) }
            }
            return out
        }
    }

    // MARK: 3. Historical NAV

    /// Fetch the most recent N NAV points (default 30).
    /// Used to render the sparkline in the expanded panel.
    func history(for code: String, limit: Int = 30) async throws -> [FundNavPoint] {
        var comps = URLComponents(string: "https://api.fund.eastmoney.com/f10/lsjz")!
        comps.queryItems = [
            .init(name: "fundCode", value: code),
            .init(name: "pageIndex", value: "1"),
            .init(name: "pageSize", value: String(limit)),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("http://fundf10.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, resp) = try await session.data(for: req)
        try Self.assertOK(resp)

        struct Envelope: Decodable {
            struct Inner: Decodable { let LSJZList: [Row] }
            struct Row: Decodable {
                let FSRQ: String  // "2026-04-24"
                let DWJZ: String  // "1.7678"
                let JZZZL: String // "0.59" (% — sometimes "" for the very first day)
            }
            let Data: Inner
        }

        let env: Envelope
        do { env = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw FundClientError.decode(error) }

        let fmt = DateFormatter.fundDate
        // Reverse so list is oldest → newest (sparkline draws left-to-right).
        return env.Data.LSJZList.reversed().compactMap { row in
            guard let d = fmt.date(from: row.FSRQ),
                  let nav = Double(row.DWJZ) else { return nil }
            let rate = Double(row.JZZZL) ?? 0.0
            return FundNavPoint(date: d, unitNav: nav, dailyRate: rate)
        }
    }

    // MARK: helpers

    private static func assertOK(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw FundClientError.badStatus(http.statusCode)
        }
    }
}

extension DateFormatter {
    static let fundDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static let fundDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
