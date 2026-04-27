//
//  FundDebugLog.swift
//  看盘侠 plugin
//
//  Plugin-bundle NSLog calls don't reliably surface in `log show` from
//  the host process — they get filtered, deduped, or eaten by the
//  subsystem. This helper writes timestamped lines to a known file so
//  we can `tail -f` it during debugging without guessing log filters.
//

import Foundation

enum FundDebugLog {
    static let path = "/tmp/fund-plugin.log"
    private static let queue = DispatchQueue(label: "fund.debug.log")
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let stamp = dateFmt.string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: path) {
                    if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                        try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
        }
    }
}
