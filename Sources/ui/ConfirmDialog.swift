//
//  ConfirmDialog.swift
//  盯基金 plugin v0.3
//
//  Programmatic confirm modal — `await ConfirmController.shared.ask(...)`
//  returns true / false. Modeled after the web's `window.confirm` so
//  callers don't have to thread modal state through their views.
//
//  Implementation: single in-flight confirm at a time (rare enough that
//  serializing is fine). The async result is delivered via a
//  CheckedContinuation captured in the request.
//

import SwiftUI

struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let confirmLabel: String
    let cancelLabel: String
    let danger: Bool
    let continuation: CheckedContinuation<Bool, Never>
}

@MainActor
final class ConfirmController: ObservableObject {
    static let shared = ConfirmController()
    private init() {}

    @Published var pending: ConfirmRequest? = nil

    /// Returns once the user picks. Resolves false if dismissed by
    /// tapping the backdrop or pressing Esc-equivalent (cancel button).
    func ask(
        title: String,
        message: String? = nil,
        confirmLabel: String = "确认",
        cancelLabel: String = "取消",
        danger: Bool = false
    ) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let req = ConfirmRequest(
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                danger: danger,
                continuation: cont
            )
            // If a confirm is already showing (shouldn't normally happen),
            // resolve the previous one as cancelled and replace it. This
            // prevents the continuation from leaking.
            if let old = pending {
                old.continuation.resume(returning: false)
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                pending = req
            }
        }
    }

    func respond(_ value: Bool) {
        guard let req = pending else { return }
        req.continuation.resume(returning: value)
        withAnimation(.easeOut(duration: 0.18)) {
            pending = nil
        }
    }
}

// MARK: - Overlay view

struct ConfirmOverlay: View {
    @ObservedObject var controller = ConfirmController.shared

    var body: some View {
        Group {
            if let req = controller.pending {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { controller.respond(false) }
                    ConfirmCard(req: req)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
    }
}

private struct ConfirmCard: View {
    let req: ConfirmRequest
    @State private var hoveredCancel = false
    @State private var hoveredConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill((req.danger ? Color.red : FundTheme.lime).opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: req.danger ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(req.danger ? Color.red : FundTheme.lime)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(req.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FundTheme.fgPrimary)
                    if let msg = req.message {
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundColor(FundTheme.fg55)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(action: { ConfirmController.shared.respond(false) }) {
                    Text(req.cancelLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(FundTheme.fg55)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(hoveredCancel ? FundTheme.overlay06 : FundTheme.overlay04)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredCancel = $0 }

                Button(action: { ConfirmController.shared.respond(true) }) {
                    Text(req.confirmLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(req.danger ? .white : .black)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(
                                req.danger
                                    ? Color(red: 0.92, green: 0.30, blue: 0.30).opacity(hoveredConfirm ? 1.0 : 0.88)
                                    : FundTheme.lime.opacity(hoveredConfirm ? 1.0 : 0.92)
                            )
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredConfirm = $0 }
            }
        }
        .padding(14)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.6), radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - View modifier

extension View {
    /// Attach the confirm dialog layer. Call once at the root of the
    /// plugin's view tree (ExpandedView).
    func confirmOverlay() -> some View {
        self.overlay(ConfirmOverlay())
    }
}
