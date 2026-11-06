import SwiftUI
import UIKit

/// 单账户 otpauth 二维码的展示载荷。只在内存中传递，不持久化。
struct ExportPayload: Identifiable {
    let id = UUID()
    let uri: String
    let title: String
    let isBound: Bool
}

/// 单账户 otpauth 二维码（屏幕展示）。
///
/// 安全约束：
/// - 必须在本地身份验证通过后才创建本视图；
/// - 只展示二维码，不提供复制密钥/链接，也不写入剪贴板、日志或文件；
/// - 默认模糊遮罩，点击后显示，60 秒自动关闭并清空画布。
struct ExportQRCodeView: View {
    let payload: ExportPayload

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var isRevealed = false
    @State private var remainingSeconds = 60
    @State private var isCountingDown = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    qrArea

                    Text("\(remainingSeconds) 秒后自动关闭并清除")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    warnings
                }
                .padding(20)
            }
            .navigationTitle("导出二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { close() }
                }
            }
        }
        .onAppear {
            image = QRCodeRenderer.makeImage(from: payload.uri)
        }
        .onDisappear {
            image = nil
        }
        .task {
            while isCountingDown && remainingSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remainingSeconds -= 1
            }
            if remainingSeconds <= 0 {
                close()
            }
        }
    }

    @ViewBuilder
    private var qrArea: some View {
        if let image {
            ZStack {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .blur(radius: isRevealed ? 0 : 26)
                    .accessibilityHidden(!isRevealed)

                if !isRevealed {
                    VStack(spacing: 10) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 30))
                        Text("点击显示二维码")
                            .font(.headline)
                        Text("显示前请确认周围无人围观")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .frame(maxWidth: 320)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isRevealed else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRevealed = true
                }
            }
            .accessibilityLabel(isRevealed ? "账户二维码，已显示" : "账户二维码，已遮挡，轻点显示")
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("无法生成二维码")
                    .font(.headline)
                Text("请关闭后重试。若问题持续，请检查账户数据是否完整。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 40)
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("这个二维码包含账户密钥，等同于密钥本身。请勿展示给他人，也不要截屏或保存到相册。")
            } icon: {
                Image(systemName: "key.horizontal")
            }
            Label {
                Text("iOS 无法阻止系统截图，显示期间请留意周围环境。")
            } icon: {
                Image(systemName: "camera.viewfinder")
            }
            if payload.isBound {
                Label {
                    Text("该账户已写入固定提交地址。导出后，任何扫码者都能独立生成动态码，防钓鱼优势失效。")
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                }
                .foregroundStyle(.orange)
            }
            Text("关闭后二维码画布会立即清空，不会保存在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func close() {
        isCountingDown = false
        isRevealed = false
        image = nil
        dismiss()
    }
}
