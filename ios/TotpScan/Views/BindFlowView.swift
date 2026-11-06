import SwiftUI

/// 绑定流程：扫码 → 域名与提交路径确认（可填备注）→ 写入 Keychain → 可选确认。
struct BindFlowView: View {
    @EnvironmentObject private var model: AppModel

    let onCompleted: () -> Void

    @State private var step: Step = .scanning
    @State private var note = ""
    @State private var errorMessage: String?

    private enum Step {
        case scanning
        case confirming(BindingPreview)
        case saved(AccountSummary)
        case confirmingServer(AccountSummary)
        case confirmFailed(AccountSummary, String)
        case done(AccountSummary)
    }

    var body: some View {
        Group {
            switch step {
            case .scanning:
                ScannerView(hint: "将服务器绑定页面上的二维码放入框内") { text in
                    handleScan(text)
                }
            case .confirming(let preview):
                confirmView(preview)
            case .saved(let account):
                savedView(account)
            case .confirmingServer:
                confirmingServerView
            case .confirmFailed(let account, let message):
                confirmFailedView(account, message)
            case .done(let account):
                doneView(account)
            }
        }
        .navigationTitle("扫描绑定二维码")
        .navigationBarTitleDisplayMode(.inline)
        .alert("绑定失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 扫码

    private func handleScan(_ text: String) {
        guard QRPayloadInspector.kind(of: text) == .binding else {
            errorMessage = "这不是绑定二维码。请扫描服务器绑定页面上的二维码。"
            return
        }
        do {
            let preview = try model.previewBinding(qrText: text)
            note = ""
            step = .confirming(preview)
        } catch {
            errorMessage = model.message(for: error)
        }
    }

    // MARK: - 地址确认

    private func confirmView(_ preview: BindingPreview) -> some View {
        Form {
            Section {
                InfoRow(label: "签发方", value: preview.issuer)
                InfoRow(label: "账户", value: preview.account)
                InfoRow(label: "算法", value: preview.algorithm.displayName)
                InfoRow(label: "位数 / 步长", value: "\(preview.digits) 位 / \(preview.period) 秒")
                if let expiresAt = preview.expiresAt {
                    InfoRow(label: "二维码有效期", value: Self.dateFormatter.string(from: expiresAt))
                }
            } header: {
                Text("即将绑定的账户")
            } footer: {
                Text("请核对签发方与账户是否为你本人所有，并确认下方注册域名与提交路径属于你要登录的站点。")
            }

            Section {
                InfoRow(label: "注册域名", value: preview.registrableDomain, monospaced: true)
                InfoRow(label: "提交路径", value: preview.submitPath, monospaced: true)
                Text(preview.submitURL)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button {
                    model.copyText(preview.submitURL, message: "提交地址已复制")
                } label: {
                    Label("复制地址", systemImage: "doc.on.doc")
                }
            } header: {
                Text("钉住的注册域名与完整提交地址")
            } footer: {
                Text(confirmedAddressFooter(preview))
            }


            Section {
                TextField("本地备注（可选，最多 \(AppModel.noteLimit) 字）", text: $note)
                    .onChange(of: note) { value in
                        if value.count > AppModel.noteLimit {
                            note = String(value.prefix(AppModel.noteLimit))
                        }
                    }
            } header: {
                Text("本地备注")
            } footer: {
                Text("备注只保存在本机，不会进入二维码，也不会发送给服务器；之后可以随时编辑或清空。")
            }

            Section {
                Button {
                    commit(preview)
                } label: {
                    Text("确认并保存").frame(maxWidth: .infinity)
                }
                Button {
                    step = .scanning
                } label: {
                    Text("重新扫描").frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func confirmedAddressFooter(_ preview: BindingPreview) -> String {
        if preview.isLooseOrigin {
            return "注意：该绑定只包含站点根路径（path 为 /），动态码会提交到 https://<dom>/。请仅在完全信任该站点时继续。"
        }
        return "登录二维码只提供域名与会话标识：域名的注册域名必须等于 \(preview.registrableDomain)；提交路径只使用绑定时的 \(preview.submitPath)，提交目标固定为上方 https://<dom><path>。"
    }

    private func commit(_ preview: BindingPreview) {
        do {
            let account = try model.commitBinding(preview, note: note)
            step = .saved(account)
        } catch {
            errorMessage = model.message(for: error)
        }
    }

    // MARK: - 保存后

    private func savedView(_ account: AccountSummary) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("绑定已保存")
                .font(.title3.weight(.semibold))
            Text("密钥、完整提交地址、注册域名与提交路径已写入本机 Keychain。还需要用当前动态码向服务器确认一次，确认后即可用于扫码登录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                startServerConfirmation(account)
            } label: {
                Text("立即确认").frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            Button("稍后确认") { onCompleted() }
                .font(.footnote)
            Spacer()
            Text("未确认的账户会显示为「待确认」，不会参与扫码登录。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .padding()
    }

    private var confirmingServerView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在向服务器确认绑定…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("跳过，稍后确认") { onCompleted() }
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func confirmFailedView(_ account: AccountSummary, _ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("绑定已保存，但确认失败")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                startServerConfirmation(account)
            } label: {
                Text("重试确认").frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            Button("稍后处理") { onCompleted() }
                .font(.footnote)
            Spacer()
        }
        .padding()
    }

    private func doneView(_ account: AccountSummary) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("绑定完成")
                .font(.title3.weight(.semibold))
            Text("「\(account.title)」已确认，可以在「扫码登录」中扫描服务器登录二维码。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                onCompleted()
            } label: {
                Text("完成").frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    private func startServerConfirmation(_ account: AccountSummary) {
        step = .confirmingServer(account)
        Task {
            do {
                let updated = try await model.confirmBinding(accountID: account.id)
                step = .done(updated)
            } catch {
                step = .confirmFailed(account, model.message(for: error))
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
