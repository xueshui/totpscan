import AVFoundation
import SwiftUI
import UIKit

/// 相机扫码控制器。只识别人脸/二维码中的 QR 码，并把内容交给上层解析。
final class CameraScanner: NSObject, ObservableObject {
    enum Status: Equatable {
        case starting
        case running
        case denied
        case restricted
        case unavailable
        case failed
    }

    @Published private(set) var status: Status = .starting

    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.scanauth.totpscan.camera")
    private var configured = false
    private var wantsRunning = false
    private var lastValue: String?
    private var lastEmittedAt = Date.distantPast

    func start() {
        wantsRunning = true
        guard AVCaptureDevice.default(for: .video) != nil else {
            status = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.status = .denied
                    }
                }
            }
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .denied
        }
    }

    func stop() {
        wantsRunning = false
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard self.configureSession() else { return }
            }
            guard self.wantsRunning else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                if self.wantsRunning {
                    self.status = .running
                }
            }
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in self?.status = .failed }
            return false
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in self?.status = .failed }
            return false
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []

        session.commitConfiguration()
        configured = true
        return true
    }

    /// 同一内容 2 秒内只上报一次，避免相机持续对焦时重复触发。
    private func shouldEmit(_ value: String) -> Bool {
        let now = Date()
        if value == lastValue, now.timeIntervalSince(lastEmittedAt) < 2 {
            return false
        }
        lastValue = value
        lastEmittedAt = now
        return true
    }
}

extension CameraScanner: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              shouldEmit(value) else {
            return
        }
        onCode?(value)
    }
}

/// 相机预览画面。
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}
