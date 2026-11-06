import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let accountID: String

    @State private var note = ""
    @State private var noteInitialized = false
    @State private var showDeleteConfirm = false
    @State private var isConfirmingBinding = false
    @State private var showBoundExportConfirm = false
    @State private var exportPayload: ExportPayload?
    @State private var isPreparingExport = false

    private var account: AccountSummary? {
        model.account(id: accountID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let account {
                    content(account)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("账户已被删除")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("账户详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .appAlert()
    }

    @ViewBuilder
    private func content(_ account: AccountSummary) -> some View {
        Form {
            if account.kind == .standard {
                codeSection(account, footer: "标准 TOTP 账户不参与扫码提交；请把动态码输入到对应网站。")
            } else if model.showBoundCodes {
                codeSection(account, footer: "扫码提交路径不变：扫码登录按注册域名匹配后，由本机提交到绑定的 https://<dom><path>。")
            } else {
                boundSection(account)
            }

            Section("账户信息") {
                InfoRow(label: "签发方", value: account.issuer)
                InfoRow(label: "账户", value: account.account)
                InfoRow(label: "类型", value: account.kind.displayName)
                InfoRow(label: "来源", value: account.source.displayName)
                InfoRow(label: "算法", value: account.algorithm.displayName)
                InfoRow(label: "位数", value: "\(account.digits) 位")
                InfoRow(label: "步长", value: "\(account.period) 秒")
                if let domain = account.registrableDomain {
                    InfoRow(label: "注册域名", value: domain, monospaced: true)
                }
                if let path = account.pinnedSubmitPath {
                    InfoRow(label: "提交路径", value: path, monospaced: true)
                }
                if let boundAt = account.boundAt {
                    InfoRow(label: "绑定时间", value: Self.dateFormatter.string(from: boundAt))
                }
            }

            Section {
                TextField("本地备注（最多 \(AppModel.noteLimit) 字）", text: $note)
                    .onChange(of: note) { value in
                        if value.count > AppModel.noteLimit {
                            note = String(value.prefix(AppModel.noteLimit))
                        }
                    }
                Button("保存备注") {
                    saveNote()
                }
                .disabled(note == account.displayName)
            } header: {
                Text("本地备注")
            } footer: {
                Text("备注只保存在本机安全存储中，不会进入二维码，也不会发送给服务器；清空后列表会显示账户名。")
            }

            Section {
                Button {
                    requestExport(account)
                } label: {
                    HStack {
                        Label("导出二维码", systemImage: "qrcode")
                        Spacer()
                        if isPreparingExport {
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparingExport)
            } header: {
                Text("导出")
            } footer: {
                if account.kind == .bound {
                    Text("导出的是标准 otpauth 二维码，仅用于屏幕展示。扫码型账户导出后，任何扫码者都能独立生成动态码，防钓鱼优势失效。")
                } else {
                    Text("导出的是标准 otpauth 二维码，仅用于屏幕展示。导出前需要 \(model.biometryLabel) 或设备密码验证，不提供复制密钥或链接。")
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text(account.kind == .bound ? "解除本机绑定" : "删除账户")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                if account.kind == .bound {
                    Text("解除绑定只会删除本机保存的密钥与提交地址，不会通知服务器。如需在服务器端撤销，请联系管理员。")
                }
            }
        }
        .onAppear {
            guard !noteInitialized else { return }
            note = account.displayName
            noteInitialized = true
        }
        .confirmationDialog(
            account.kind == .bound ? "确定解除本机绑定？" : "确定删除该账户？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(account.kind == .bound ? "解除绑定" : "删除", role: .destructive) {
                performDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(account.kind == .bound
                 ? "删除后，本机将无法再为该站点扫码提交动态码。"
                 : "删除后，本机将无法再生成该账户的动态码。请确认已在其他认证器中保留备份。")
        }
        .confirmationDialog(
            "导出该扫码型账户的密钥？",
            isPresented: $showBoundExportConfirm,
            titleVisibility: .visible
        ) {
            Button("我已了解风险，继续导出") {
                prepareExport(account)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("导出后该账户的防钓鱼优势失效，任何扫码者都能独立生成动态码。")
        }
        .sheet(item: $exportPayload) { payload in
            ExportQRCodeView(payload: payload)
        }
    }

    private func codeSection(_ account: AccountSummary, footer: String) -> some View {
        Section {
            VStack(spacing: 14) {
                if let code = model.codes[account.id] {
                    Button {
                        model.copyCode(code.value)
                    } label: {
                        VStack(spacing: 12) {
                            CodeText(value: code.value, size: 36)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                CountdownRing(
                                    remaining: code.remainingSeconds(),
                                    period: code.period,
                                    size: 24
                                )
                                Text("\(code.remainingSeconds()) 秒后刷新")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "doc.on.doc")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("动态码 \(code.value)，点击复制")
                } else {
                    Text("暂时无法计算动态码，请检查账户数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("点击动态码可复制，剪贴板内容 60 秒后自动清除。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if account.kind == .bound {
                    Text("你已在设置中开启扫码型账户动态码显示：该码对旁人可见，防钓鱼优势下降。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        } footer: {
            Text(footer)
        }
    }

    private func boundSection(_ account: AccountSummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    KindBadge(kind: .bound)
                    if account.isConfirmed {
                        StatusPill(text: "已确认", color: .green)
                    } else {
                        StatusPill(text: "待确认", color: .orange)
                    }
                }

                Text("该账户的动态码默认不在界面上显示。请到「扫码登录」扫描服务器登录页的二维码，本机比对地址成功后直接提交。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("如需在其他认证器中使用，可在本页「导出二维码」中查看；导出需要额外确认，且会削弱防钓鱼保护。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if account.isConfirmed {
                    Text("只有扫描到注册域名相同的登录二维码时，本机才会计算并提交动态码；提交路径只使用绑定时的 path。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("绑定尚未确认。未确认的账户不会参与扫码登录，请先完成确认。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button {
                        confirmBinding(account)
                    } label: {
                        if isConfirmingBinding {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在确认…")
                            }
                        } else {
                            Text("完成绑定确认")
                        }
                    }
                    .disabled(isConfirmingBinding)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func saveNote() {
        do {
            try model.rename(accountID: accountID, note: note)
        } catch {
            model.present(error)
        }
    }

    private func performDelete() {
        do {
            try model.delete(accountID: accountID)
            dismiss()
        } catch {
            model.present(error)
        }
    }

    private func confirmBinding(_ account: AccountSummary) {
        guard !isConfirmingBinding else { return }
        isConfirmingBinding = true
        Task {
            do {
                _ = try await model.confirmBinding(accountID: account.id)
            } catch {
                model.present(error)
            }
            isConfirmingBinding = false
        }
    }

    /// 扫码型账户先给出防钓鱼失效警告，标准账户直接进入身份验证。
    private func requestExport(_ account: AccountSummary) {
        guard !isPreparingExport else { return }
        if account.kind == .bound {
            showBoundExportConfirm = true
        } else {
            prepareExport(account)
        }
    }

    /// 本地认证通过后才生成 URI 并渲染二维码；认证失败不创建任何界面。
    private func prepareExport(_ account: AccountSummary) {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        Task {
            do {
                try await model.authenticateForExport()
                let uri = try model.otpauthURI(for: account.id)
                exportPayload = ExportPayload(
                    uri: uri,
                    title: account.title,
                    isBound: account.kind == .bound
                )
            } catch {
                model.present(error)
            }
            isPreparingExport = false
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
