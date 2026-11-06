import SwiftUI

/// 开启「显示扫码型账户动态码」前的风险确认与本地认证。
struct BoundCodeRiskView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var acknowledged = false
    @State private var isEnabling = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("开启后，扫码型账户的六位动态码会直接显示在账户列表和详情页，并可点击复制。")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)

                    Text("旁人可能看到屏幕上的动态码，扫码提交的防钓鱼优势会下降。只在确认环境安全时开启。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("风险说明")
                }

                Section {
                    Toggle("我已了解风险，确认开启", isOn: $acknowledged)
                } footer: {
                    Text("开启前需要 \(model.biometryLabel) 或设备密码验证。关闭开关后会立即隐藏并清除所有扫码型账户的动态码。")
                }
            }
            .navigationTitle("显示扫码型账户动态码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开启") { enable() }
                        .disabled(!acknowledged || isEnabling)
                }
            }
        }
        .appAlert()
    }

    private func enable() {
        guard acknowledged, !isEnabling else { return }
        isEnabling = true
        Task {
            do {
                try await model.enableBoundCodes()
                dismiss()
            } catch {
                model.present(error)
            }
            isEnabling = false
        }
    }
}
