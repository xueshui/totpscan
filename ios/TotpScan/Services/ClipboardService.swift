import UIKit
import UniformTypeIdentifiers

/// 剪贴板工具。动态码只保留 60 秒，避免长期残留在系统剪贴板。
enum ClipboardService {
    static func copy(_ value: String) {
        guard !value.isEmpty else { return }
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )
    }
}
