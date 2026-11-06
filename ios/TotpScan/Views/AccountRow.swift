import SwiftUI

struct AccountRow: View {
    let account: AccountSummary
    let code: TotpCode?
    let onOpen: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(account.title)
                            .font(.headline)
                            .lineLimit(1)
                        KindBadge(kind: account.kind)
                    }
                    Text(account.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if account.kind == .bound {
                        Text(account.isConfirmed ? "可在登录页扫码提交" : "待确认，暂不可登录")
                            .font(.caption2)
                            .foregroundStyle(account.isConfirmed ? Color.secondary : Color.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let code {
                Button(action: onCopy) {
                    VStack(spacing: 6) {
                        CodeText(value: code.value, size: 20)
                        HStack(spacing: 6) {
                            CountdownRing(
                                remaining: code.remainingSeconds(),
                                period: code.period,
                                size: 20
                            )
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("动态码 \(code.value)，点击复制")
            } else {
                Image(systemName: account.kind == .bound ? "qrcode" : "clock")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(account.kind == .bound ? "扫码绑定账户" : "标准 TOTP 账户")
            }
        }
        .padding(.vertical, 4)
    }
}
