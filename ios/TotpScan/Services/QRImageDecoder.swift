import UIKit
import Vision

/// 从相册图片中识别二维码（相机不可用或权限被拒时的兜底）。
enum QRImageDecoder {
    static func decode(_ image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let first = request.results?.first as? VNBarcodeObservation else {
            return nil
        }
        return first.payloadStringValue
    }
}
