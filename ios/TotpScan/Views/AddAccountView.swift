import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        BindFlowView(onCompleted: { dismiss() })
                    } label: {
                        optionRow(
                            icon: "qrcode.viewfinder",
                            tint: .orange,
                            title: "扫描绑定二维码",
                            subtitle: "从服务器绑定页面获取密钥与固定提交地址"
                        )
                    }

                    NavigationLink {
                        ImportOTPAuthView(onCompleted: { dismiss() })
                    } label: {
                        optionRow(
                            icon: "link",
                            tint: .accentColor,
                            title: "导入 otpauth 链接",
                            subtitle: "粘贴 otpauth://totp/… 链接，兼容标准认证器"
                        )
                    }

                    NavigationLink {
                        ManualEntryView(onCompleted: { dismiss() })
                    } label: {
                        optionRow(
                            icon: "keyboard",
                            tint: .accentColor,
                            title: "手动输入密钥",
                            subtitle: "输入 Base32 密钥与参数，生成标准 TOTP 账户"
                        )
                    }
                } header: {
                    Text("添加方式")
                } footer: {
                    Text("标准 TOTP 账户只保存在本机，可显示动态码；扫码绑定账户会固化提交地址，只能通过扫码提交。")
                }
            }
            .navigationTitle("添加账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func optionRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
