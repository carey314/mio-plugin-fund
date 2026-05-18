//
//  Toast.swift
//  盯基金 plugin v0.3
//
//  Lightweight in-panel toast for operation feedback. Sits as an
//  overlay on top of ExpandedView so it floats above the active tab.
//  Auto-dismisses after ~2.6s, manually dismissible by click.
//
//  Design: matches the rest of the plugin — lime accent for success,
//  red for error, muted yellow for info. SF Symbol leading icon.
//  Slides in from the top with a spring, fades out on exit.
//
//  Usage from anywhere inside the plugin tree:
//      ToastController.shared.success("已添加 易方达蓝筹")
//      ToastController.shared.error("加载失败,请重试")
//      ToastController.shared.info("数据已刷新")
//

import SwiftUI

enum ToastKind {
    case success
    case error
    case info

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success: return FundTheme.lime
        case .error:   return Color(red: 1.0,  green: 0.34, blue: 0.34)
        case .info:    return Color(red: 1.0,  green: 0.72, blue: 0.0)
        }
    }
}

struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let kind: ToastKind
    let message: String
}

@MainActor
final class ToastController: ObservableObject {
    static let shared = ToastController()
    private init() {}

    @Published var toasts: [ToastItem] = []

    private let durationSeconds: Double = 2.6

    func show(_ kind: ToastKind, _ message: String) {
        let item = ToastItem(id: UUID(), kind: kind, message: message)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            toasts.append(item)
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.durationSeconds ?? 2.6) * 1_000_000_000)
            await MainActor.run { [weak self] in
                self?.dismiss(item.id)
            }
        }
    }

    func success(_ message: String) { show(.success, message) }
    func error(_ message: String)   { show(.error, message) }
    func info(_ message: String)    { show(.info, message) }

    func dismiss(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.18)) {
            toasts.removeAll { $0.id == id }
        }
    }
}

// MARK: - Overlay view

struct ToastOverlay: View {
    @ObservedObject var controller = ToastController.shared

    var body: some View {
        VStack(spacing: 6) {
            ForEach(controller.toasts) { toast in
                ToastRow(item: toast, onDismiss: { controller.dismiss(toast.id) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            Spacer()
        }
        .padding(.top, 48)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(!controller.toasts.isEmpty)
    }
}

private struct ToastRow: View {
    let item: ToastItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(item.kind.tint)
            Text(item.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FundTheme.fgPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(item.kind.tint.opacity(0.32), lineWidth: 0.8)
                )
                .shadow(color: item.kind.tint.opacity(0.18), radius: 8, x: 0, y: 4)
        )
        .onTapGesture { onDismiss() }
    }
}

// MARK: - View modifier

extension View {
    /// Attach the toast layer to a container. Call once at the root of
    /// the plugin's view tree (ExpandedView) — `ToastController.shared`
    /// is a singleton so any view in the tree can push toasts without
    /// further wiring.
    func toastOverlay() -> some View {
        self.overlay(ToastOverlay())
    }
}
