import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddAccount = false
    @State private var selectedAccount: AccountSummary?

    var body: some View {
        NavigationStack {
            Group {
                if !model.loaded {
                    ProgressView("正在读取本机账户…")
                } else if model.accounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle("账户")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddAccount = true
                    } label: {
                        Label("添加账户", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountView()
            }
            .sheet(item: $selectedAccount) { account in
                AccountDetailView(accountID: account.id)
            }
        }
    }

    private var accountList: some View {
        List {
            if model.hasDriftWarning, let description = model.driftDescription {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(description).font(.footnote.weight(.medium))
                            Text("时间偏差过大会导致动态码被服务器拒绝。建议在系统设置中开启「自动设置时间」。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
                    }
                }
            }

            if !model.boundAccounts.isEmpty {
                Section {
                    ForEach(model.boundAccounts) { account in
                        row(account)
                    }
                } header: {
                    Text("扫码绑定账户（\(model.boundAccounts.count)）")
                } footer: {
                    if model.showBoundCodes {
                        Text("已开启扫码型账户动态码显示：动态码对旁人可见，防钓鱼优势下降。扫码提交仍按注册域名匹配后由本机提交。")
                    } else {
                        Text("这类账户保存了固定提交地址，默认不显示动态码，只能在「扫码登录」中由本机按注册域名匹配后直接提交；如需在其他认证器中使用，可在账户详情页导出二维码。")
                    }
                }
            }

            if !model.standardAccounts.isEmpty {
                Section {
                    ForEach(model.standardAccounts) { account in
                        row(account)
                    }
                } header: {
                    Text("标准 TOTP 账户（\(model.standardAccounts.count)）")
                } footer: {
                    Text("兼容 RFC 6238 与 Google Authenticator 等标准认证器，可显示并复制动态码；不参与扫码提交。动态码对设备时间敏感，请在系统设置中开启「自动设置时间」。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await model.reload()
            await model.refreshDrift()
        }
        .onAppear {
            model.reload()
            Task { await model.refreshDrift() }
        }
    }

    private func row(_ account: AccountSummary) -> some View {
        AccountRow(
            account: account,
            code: model.codes[account.id],
            onOpen: { selectedAccount = account },
            onCopy: {
                if let code = model.codes[account.id] {
                    model.copyCode(code.value)
                }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(account)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("还没有添加账户")
                .font(.title3.weight(.semibold))
            Text("可以扫描服务器提供的绑定二维码，或导入标准 TOTP 账户。所有密钥只保存在本机安全存储中。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                showAddAccount = true
            } label: {
                Label("添加账户", systemImage: "plus.circle.fill")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
            VStack(spacing: 4) {
                Text("提示：标准 TOTP 账户和扫码绑定账户可以同时存在。")
                Text("两类账户在列表中用不同标签区分。")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 24)
        }
        .padding()
    }

    private func delete(_ account: AccountSummary) {
        do {
            try model.delete(accountID: account.id)
        } catch {
            model.present(error)
        }
    }
}
