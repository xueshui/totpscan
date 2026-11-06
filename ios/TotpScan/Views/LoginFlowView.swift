import SwiftUI

/// 扫码登录：解析二维码 → 按注册域名匹配本机账户 → 身份验证 → 提交到绑定时的 `https://<dom><path>`。
/// 候选为 0 时完全本地终止，不发起任何网络请求。
struct LoginFlowView: View {
    @EnvironmentObject private var model: AppModel

    @State private var step: Step = .scanning

    private enum Step {
        case scanning
        case selecting(accounts: [AccountSummary], qrText: String)
        case confirming(LoginApproval)
        case submitting
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .scanning:
                    ScannerView(hint: "扫描登录页上的二维码\n本机会按注册域名匹配已绑定账户") { text in
                        handleScan(text)
                    }
                case .selecting(let accounts, let qrText):
                    selectingView(accounts, qrText)
                case .confirming(let approval):
                    confirmingView(approval)
                case .submitting:
                    submittingView
                case .success:
                    resultView(
                        symbol: "checkmark.circle.fill",
                        tint: .green,
                        title: "登录请求已提交",
                        message: "请回到浏览器查看登录状态。若浏览器提示失败，请刷新二维码后重试。"
                    )
                case .failure(let message):
                    resultView(
                        symbol: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: "未能完成扫码登录",
                        message: message
                    )
                }
            }
            .navigationTitle("扫码登录")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 扫码分流

    private func handleScan(_ text: String) {
        switch QRPayloadInspector.kind(of: text) {
        case .login:
            resolveLogin(text)
        case .binding:
            step = .failure("这是绑定二维码。请到「账户 → 添加账户 → 扫描绑定二维码」中完成绑定。")
        case .otpAuth:
            step = .failure("这是标准 TOTP 链接。请到「账户 → 添加账户 → 导入 otpauth 链接」中导入。")
        case .unknown:
            step = .failure("无法识别这个二维码。请扫描服务器登录页上的二维码。")
        }
    }

    private func resolveLogin(_ text: String) {
        do {
            let approval = try model.prepareLogin(qrText: text)
            step = .confirming(approval)
        } catch let error as TotpScanError {
            switch error {
            case .multipleMatchingAccounts(let accounts):
                step = .selecting(accounts: accounts, qrText: text)
            case .noMatchingAccount:
                step = .failure("未找到与该二维码注册域名匹配的已绑定账户。为保护安全，本机没有发起任何网络请求。")
            default:
                step = .failure(error.errorDescription ?? "二维码无效或已过期")
            }
        } catch {
            step = .failure(model.message(for: error))
        }
    }

    // MARK: - 候选选择

    private func selectingView(_ accounts: [AccountSummary], _ qrText: String) -> some View {
        List {
            Section {
                Text("有 \(accounts.count) 个本机账户与二维码的注册域名匹配。只会显示同域账户，请选择要使用的账户。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(accounts) { account in
                    Button {
                        choose(account, qrText: qrText)
                    } label: {
                        candidateRow(account)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                Button("取消") { step = .scanning }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func candidateRow(_ account: AccountSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(account.title)
                    .font(.body.weight(.medium))
                KindBadge(kind: .bound)
            }
            if !account.displayName.isEmpty {
                Text("\(account.issuer) · \(account.account)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let domain = account.registrableDomain, let path = account.pinnedSubmitPath {
                Text("\(domain) · \(path)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let pinned = account.pinnedSubmitURL {
                Text(pinned)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func choose(_ account: AccountSummary, qrText: String) {
        do {
            let approval = try model.prepareLogin(qrText: qrText, preferredAccountID: account.id)
            step = .confirming(approval)
        } catch {
            step = .failure(model.message(for: error))
        }
    }

    // MARK: - 确认与提交

    private func confirmingView(_ approval: LoginApproval) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(approval.issuer)
                        .font(.headline)
                    Text(approval.account)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    KindBadge(kind: .bound)
                }
                .padding(.vertical, 4)
            } header: {
                Text("将使用本机账户")
            }

            Section {
                InfoRow(label: "注册域名", value: approval.registrableDomain, monospaced: true)
                Text(approval.submitURL)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("提交目标（绑定时的完整地址）")
            } footer: {
                Text(approval.isLooseOrigin
                     ? "该账户绑定的是站点根路径，提交目标为 https://<dom>/。请确认你信任该站点；二维码中的域名不会被用来拼接提交路径。"
                     : "二维码只提供域名与会话标识；提交路径只使用绑定时的 path。动态码始终提交到上方地址，二维码中的域名不会被用来拼接路径。")
            }

            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(approval.expiresAt.timeIntervalSince(context.date)))
                    HStack {
                        Image(systemName: "timer")
                            .foregroundStyle(remaining <= 10 ? Color.orange : Color.secondary)
                        Text(remaining > 0 ? "登录二维码将在 \(remaining) 秒后失效" : "登录二维码已过期，请刷新后重新扫描")
                            .font(.footnote)
                            .foregroundStyle(remaining <= 10 ? Color.orange : Color.secondary)
                    }
                }
                Button {
                    startSubmit(approval)
                } label: {
                    Text("验证身份并提交").frame(maxWidth: .infinity)
                }
                Button("取消") { step = .scanning }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("提交前需要 \(model.biometryLabel) 验证。动态码只在提交瞬间计算，不会显示在本机界面上。")
            }
        }
    }

    private var submittingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在验证身份并提交…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startSubmit(_ approval: LoginApproval) {
        step = .submitting
        Task {
            do {
                try await model.authenticateForSubmit()
                _ = try await model.submit(approval)
                step = .success
            } catch let error as DeviceAuthError {
                if case .cancelled = error {
                    step = .failure("已取消身份验证，动态码没有提交。")
                } else {
                    step = .failure(error.errorDescription ?? "身份验证失败，动态码没有提交。")
                }
            } catch {
                step = .failure(model.message(for: error))
            }
        }
    }

    // MARK: - 结果

    private func resultView(symbol: String, tint: Color, title: String, message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 54))
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                step = .scanning
            } label: {
                Text("继续扫码").frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
}
