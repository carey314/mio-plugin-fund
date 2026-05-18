//
//  FundPlugin.swift
//  Mio Island plugin: 盯基金
//
//  Principal class. Module = FundPlugin, Class = FundPlugin →
//  NSPrincipalClass = "FundPlugin.FundPlugin".
//

import AppKit
import SwiftUI

final class FundPlugin: NSObject, MioPlugin {
    var id: String { "fund" }
    var name: String { "看盘侠" }
    var icon: String { "chart.line.uptrend.xyaxis" }
    var version: String { "0.3.0" }

    func activate() {
        FundDebugLog.write("plugin activate")
        // Kick off the refresh loops as soon as the plugin enables.
        // The store is a singleton so the loops survive panel show/hide.
        Task { @MainActor in
            FundStore.shared.start()
            await FundStore.shared.refreshNow()
        }
    }

    func deactivate() {
        FundDebugLog.write("plugin deactivate")
        Task { @MainActor in
            FundStore.shared.stop()
        }
    }

    func makeView() -> NSView {
        let view = NSHostingView(rootView: ExpandedView())
        view.autoresizingMask = [.width, .height]
        return view
    }

    @objc func viewForSlot(_ slot: String, context: [String: Any]) -> NSView? {
        switch slot {
        case "header":
            let v = NSHostingView(rootView: HeaderSlotView())
            v.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
            v.setFrameSize(NSSize(width: 20, height: 20))
            return v
        default:
            return nil
        }
    }
}
