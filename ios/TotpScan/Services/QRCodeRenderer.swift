import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 使用系统 Core Image 在本地生成二维码，不依赖任何在线服务。
/// 生成结果只存在于内存中，不写入相册或文件。
enum QRCodeRenderer {
    static func makeImage(from text: String, scale: CGFloat = 12) -> UIImage? {
        guard !text.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
