import SwiftUI

/// 倒计时环。剩余时间不足 20% 时变红，提醒用户即将换码。
struct CountdownRing: View {
    let remaining: Int
    let period: Int
    var size: CGFloat = 24

    private var progress: Double {
        guard period > 0 else { return 0 }
        return min(1, max(0, Double(remaining) / Double(period)))
    }

    private var tint: Color {
        progress <= 0.2 ? .red : .accentColor
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.22), lineWidth: max(2, size * 0.12))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: max(2, size * 0.12), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            Text("\(remaining)")
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }
}

/// 动态码展示：按 3/3 或 4/4 分组，便于口头报码。
struct CodeText: View {
    let value: String
    var size: CGFloat = 28

    private var groups: [String] {
        guard value.count > 2 else { return [value] }
        let middle = (value.count + 1) / 2
        return [String(value.prefix(middle)), String(value.dropFirst(middle))]
    }

    var body: some View {
        HStack(spacing: size * 0.22) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Text(group)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .kerning(1)
    }
}

/// 账户类型标签，确保列表里一眼能区分两类账户。
struct KindBadge: View {
    let kind: AccountKind

    private var title: String {
        kind == .bound ? "扫码提交" : "标准 TOTP"
    }

    private var symbol: String {
        kind == .bound ? "qrcode.viewfinder" : "clock.arrow.circlepath"
    }

    private var tint: Color {
        kind == .bound ? .orange : .accentColor
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .footnote.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// 统一的弹窗与轻提示。
struct AppAlertModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content.alert(
            "提示",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { presented in
                    if !presented { model.alertMessage = nil }
                }
            )
        ) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

struct ToastModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = model.toastMessage {
                Text(message)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toastMessage)
    }
}

extension View {
    func appAlert() -> some View { modifier(AppAlertModifier()) }
    func appToast() -> some View { modifier(ToastModifier()) }
}
