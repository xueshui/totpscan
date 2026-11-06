import PhotosUI
import SwiftUI
import UIKit

/// 通用扫码视图：相机不可用、权限被拒时提供相册与粘贴兜底。
struct ScannerView: View {
    let hint: String
    let onCode: (String) -> Void

    @StateObject private var scanner = CameraScanner()
    @State private var photoItem: PhotosPickerItem?
    @State private var manualText = ""
    @State private var showManualEntry = false
    @State private var photoError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch scanner.status {
            case .starting:
                ProgressView("正在启动相机…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .running:
                CameraPreview(session: scanner.session)
                    .ignoresSafeArea()
                scanOverlay
            case .denied:
                permissionView(
                    title: "相机权限未开启",
                    message: "需要在系统设置中允许「扫码认证器」使用相机，才能扫描二维码。",
                    showsSettingsButton: true
                )
            case .restricted:
                permissionView(
                    title: "相机被系统限制",
                    message: "此设备限制了相机访问（可能由家长控制或设备管理策略导致）。可以使用相册或粘贴二维码内容。",
                    showsSettingsButton: false
                )
            case .unavailable:
                permissionView(
                    title: "相机不可用",
                    message: "当前设备没有可用的相机。可以使用相册图片或粘贴二维码内容。",
                    showsSettingsButton: false
                )
            case .failed:
                permissionView(
                    title: "相机启动失败",
                    message: "无法初始化相机。可以使用相册图片或粘贴二维码内容。",
                    showsSettingsButton: false
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            fallbackBar
        }
        .onAppear {
            scanner.onCode = onCode
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
        .onChange(of: photoItem) { item in
            loadPhoto(item)
        }
        .sheet(isPresented: $showManualEntry) {
            manualEntrySheet
        }
        .alert("无法识别图片", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("好", role: .cancel) { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
    }

    private var scanOverlay: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 240, height: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 6)
                        .blur(radius: 6)
                )
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 20)
            Spacer()
        }
        .padding(.bottom, 80)
    }

    private func permissionView(title: String, message: String, showsSettingsButton: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if showsSettingsButton {
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var fallbackBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("相册图片", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showManualEntry = true
            } label: {
                Label("粘贴内容", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var manualEntrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $manualText)
                        .frame(minHeight: 120)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("二维码内容")
                } footer: {
                    Text("把二维码中的文本完整粘贴到此处。内容只在本机解析。")
                }
            }
            .navigationTitle("粘贴二维码内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        manualText = ""
                        showManualEntry = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用") {
                        let value = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        showManualEntry = false
                        manualText = ""
                        onCode(value)
                    }
                    .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    photoError = "无法读取所选图片。"
                    photoItem = nil
                    return
                }
                guard let value = QRImageDecoder.decode(image) else {
                    photoError = "图片中没有识别到二维码，请换一张更清晰的图片。"
                    photoItem = nil
                    return
                }
                photoItem = nil
                onCode(value)
            } catch {
                photoItem = nil
                photoError = "读取图片失败，请重试。"
            }
        }
    }
}
