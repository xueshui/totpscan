import SwiftUI
import UIKit

struct ImportOTPAuthView: View {
    @EnvironmentObject private var model: AppModel

    let onCompleted: () -> Void

    @State private var uri = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $uri)
                    .frame(minHeight: 120)
                    .font(.footnote.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .overlay(alignment: .topLeading) {
                        if uri.isEmpty {
                            Text("otpauth://totp/Example:alice@example.com?secret=…")
                                .font(.footnote.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                Button {
                    if let value = UIPasteboard.general.string {
                        uri = value
                    }
                } label: {
                    Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                }
            } header: {
                Text("otpauth 链接")
            } footer: {
                Text("支持 issuer、account、secret、algorithm（SHA1/SHA256/SHA512）、digits（6/8）、period 参数。仅支持 totp 类型。")
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
                    Text("导入账户").frame(maxWidth: .infinity)
                }
                .disabled(uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("导入链接")
        .navigationBarTitleDisplayMode(.inline)
        .alert("无法导入账户", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.addStandardAccount(fromOTPAuthURI: trimmed, note: note)
            onCompleted()
        } catch {
            errorMessage = model.message(for: error)
        }
    }
}
