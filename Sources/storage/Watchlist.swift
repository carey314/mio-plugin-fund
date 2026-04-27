//
//  Watchlist.swift
//  盯基金 plugin v0.2
//
//  User's selected funds + their cost basis / shares (when set).
//  Persisted as JSON to:
//    ~/Library/Application Support/Mio Island/Fund/watchlist.json
//

import Foundation

@MainActor
final class Watchlist: ObservableObject {
    @Published private(set) var funds: [WatchlistFund] = []

    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.mioisland.plugin.fund.watchlist", qos: .userInitiated)

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Mio Island/Fund", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storeURL = dir.appendingPathComponent("watchlist.json")
        load()
    }

    // MARK: - Public API

    func add(_ hit: FundSearchHit) {
        guard !funds.contains(where: { $0.code == hit.code }) else { return }
        let item = WatchlistFund(
            code: hit.code, name: hit.name,
            addedAt: Date(),
            displayOrder: (funds.map { $0.displayOrder }.max() ?? 0) + 1,
            shares: nil, costNav: nil
        )
        funds.append(item)
        save()
    }

    func remove(code: String) {
        funds.removeAll { $0.code == code }
        save()
    }

    func updatePosition(code: String, shares: Double?, costNav: Double?) {
        guard let idx = funds.firstIndex(where: { $0.code == code }) else { return }
        var f = funds[idx]
        f.shares = shares
        f.costNav = costNav
        funds[idx] = f
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        funds.move(fromOffsets: source, toOffset: destination)
        for (idx, var f) in funds.enumerated() {
            f.displayOrder = idx
            funds[idx] = f
        }
        save()
    }

    func contains(_ code: String) -> Bool {
        funds.contains { $0.code == code }
    }

    var codes: [String] { funds.map(\.code) }

    func fund(code: String) -> WatchlistFund? {
        funds.first { $0.code == code }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            let decoded = try JSONDecoder.fundDecoder.decode([WatchlistFund].self, from: data)
            self.funds = decoded.sorted(by: { $0.displayOrder < $1.displayOrder })
        } catch {
            NSLog("[fund-plugin] watchlist load failed: \(error)")
        }
    }

    private func save() {
        let snapshot = self.funds
        queue.async { [storeURL] in
            do {
                let encoder = JSONEncoder.fundEncoder
                let data = try encoder.encode(snapshot)
                let tmp = storeURL.appendingPathExtension("tmp")
                try data.write(to: tmp, options: .atomic)
                _ = try? FileManager.default.replaceItemAt(storeURL, withItemAt: tmp)
            } catch {
                NSLog("[fund-plugin] watchlist save failed: \(error)")
            }
        }
    }
}

private extension JSONEncoder {
    static var fundEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var fundDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
