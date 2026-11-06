import SwiftUI

struct ManualEntryView: View {
    @EnvironmentObject private var model: AppModel

    let onCompleted: () -> Void

    @State private var issuer = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var algorithm: OtpAlgorithm = .sha1
    @State private var digits = 6
    @State private var periodText = "30"
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("签发方（可选）", text: $issuer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("账户（邮箱或用户名）", text: $account)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Base32 密钥", text: $secret)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("账户")
            } footer: {
                Text("密钥通常由网站提供，形如 JBSWY3DPEHPK3PXP。请确认来源可信。")
            }

            Section("参数") {
                Picker("算法", selection: $algorithm) {
                    ForEach(OtpAlgorithm.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                Picker("位数", selection: $digits) {
                    Text("6 位").tag(6)
                    Text("8 位").tag(8)
                }
                HStack {
                    Text("步长（秒）")
                    Spacer()
                    TextField("30", text: $periodText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section {
                TextField("本地备注（可选，最多 \(AppModel.noteLimit) 字）", text: $note)
                    .onChange(of: note) { value in
                        if value.count > AppModel.noteLimit {
                            note = String(value.prefix(AppModel.noteLimit))
                        }
                    }
            } footer: {
                Text("备注只保存在本机，不会发送给服务器。")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("添加账户").frame(maxWidth: .infinity)
                }
                .disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("手动输入")
        .navigationBarTitleDisplayMode(.inline)
        .alert("无法添加账户", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard let period = Int(periodText.trimmingCharacters(in: .whitespaces)), (1...3600).contains(period) else {
            errorMessage = "步长必须是 1–3600 之间的整数秒。"
            return
        }
        do {
            try model.addStandardAccount(
                issuer: issuer,
                account: account,
                secret: secret,
                algorithm: algorithm,
                digits: digits,
                period: period,
                note: note
            )
            onCompleted()
        } catch {
            errorMessage = model.message(for: error)
        }
    }
}
