import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var showClearConfirm = false
    @State private var showBoundCodeRisk = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("标准 TOTP 账户", systemImage: "clock.arrow.circlepath")
                            .font(.footnote.weight(.semibold))
                        Text("兼容 RFC 6238，可显示、复制动态码，不参与扫码提交。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("扫码绑定账户", systemImage: "qrcode.viewfinder")
                            .font(.footnote.weight(.semibold))
                            .padding(.top, 4)
                        Text("保存固定提交地址，默认不显示动态码，只能在扫码登录中按地址匹配后提交；可在账户详情页导出 otpauth 二维码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("账户类型")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { model.showBoundCodes },
                        set: { newValue in
                            if newValue {
                                showBoundCodeRisk = true
                            } else {
                                model.disableBoundCodes()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("显示扫码型账户的动态码")
                            Text(model.showBoundCodes ? "已开启：旁人也可能看到动态码" : "默认关闭：扫码型账户不显示动态码")
                                .font(.caption)
                                .foregroundStyle(model.showBoundCodes ? Color.orange : Color.secondary)
                        }
                    }

                    HStack {
                        Text("提交前验证")
                        Spacer()
                        Text(model.biometryLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("验证失败")
                        Spacer()
                        Text("终止提交")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("安全")
                } footer: {
                    Text("每次扫码提交前都会要求 Face ID / Touch ID 验证；生物识别不可用时才允许回退到设备密码。验证失败或取消时不会计算、也不会提交动态码。开启「显示扫码型账户的动态码」需要再次身份验证并确认风险；关闭后会立即隐藏并清除。")
                }

                Section {
                    HStack {
                        Text("设备时间")
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.timeFormatter.string(from: context.date))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("服务器时间偏差")
                        Spacer()
                        if model.isRefreshingDrift {
                            ProgressView()
                        } else {
                            Text(model.driftDescription ?? "暂无可用服务器")
                                .font(.footnote)
                                .foregroundStyle(model.hasDriftWarning ? Color.orange : Color.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Button {
                        Task { await model.refreshDrift() }
                    } label: {
                        Label("重新检测时间偏差", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshingDrift || model.boundAccounts.isEmpty)
                } header: {
                    Text("时间")
                } footer: {
                    Text("时间偏差检测会向已确认绑定账户的固化地址同源发送一次 HEAD /healthz 请求，不携带任何凭据。偏差超过 5 秒时会在账户列表顶部提示。")
                }

                Section {
                    HStack {
                        Text("网络")
                        Spacer()
                        Text("仅 HTTPS / TLS 1.2+")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("重定向")
                        Spacer()
                        Text("不跟随")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Cookie")
                        Spacer()
                        Text("不使用")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://support.apple.com/zh-cn/HT204306")!) {
                        Label("了解 iOS 安全存储", systemImage: "lock.shield")
                    }
                } header: {
                    Text("网络与存储")
                } footer: {
                    Text("共享密钥、完整提交地址与备注保存在 Keychain（本设备、解锁后可读、不参与 iCloud 同步）。所有二维码内容均按不可信输入处理。单账户导出的 otpauth 链接是标准明文格式，导出后该账户的防钓鱼优势会失效。")
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("清空本机所有账户")
                    }
                    .disabled(model.accounts.isEmpty)
                } footer: {
                    Text("该操作会删除本机保存的所有密钥与提交地址，且无法恢复。服务器端绑定需要管理员处理。")
                }

                Section {
                    InfoRow(label: "版本", value: Self.versionText)
                    InfoRow(label: "协议", value: "TOTPSCAN/v1")
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .confirmationDialog(
                "确定清空所有账户？",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("清空所有账户", role: .destructive) {
                    do {
                        try model.clearAllAccounts()
                    } catch {
                        model.present(error)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可撤销，请确认已妥善备份标准 TOTP 账户的密钥。")
            }
            .sheet(isPresented: $showBoundCodeRisk) {
                BoundCodeRiskView()
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
