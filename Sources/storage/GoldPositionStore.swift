//
//  GoldPositionStore.swift
//  盯基金 plugin v0.2
//
//  Persists the single GoldPosition to its own JSON file (separate
//  from watchlist.json — different shape, different lifecycle).
//
//  Path: ~/Library/Application Support/Mio Island/Fund/gold-position.json
//

import Foundation

@MainActor
final class GoldPositionStore: ObservableObject {
    @Published private(set) var position: GoldPosition = GoldPosition(grams: nil, costPerGram: nil)

    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.mioisland.plugin.fund.gold-position", qos: .userInitiated)

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Mio Island/Fund", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storeURL = dir.appendingPathComponent("gold-position.json")
        load()
    }

    func update(grams: Double?, costPerGram: Double?) {
        position = GoldPosition(grams: grams, costPerGram: costPerGram)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(GoldPosition.self, from: data) else {
            return
        }
        position = decoded
    }

    private func save() {
        let snapshot = position
        queue.async { [storeURL] in
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                let tmp = storeURL.appendingPathExtension("tmp")
                try data.write(to: tmp, options: .atomic)
                _ = try? FileManager.default.replaceItemAt(storeURL, withItemAt: tmp)
            } catch {
                NSLog("[fund-plugin] gold position save failed: \(error)")
            }
        }
    }
}
