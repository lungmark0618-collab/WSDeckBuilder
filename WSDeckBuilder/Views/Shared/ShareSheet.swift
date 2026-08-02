import SwiftUI
import UIKit

/// UIActivityViewController 的包裝。ShareLink 要在按下前就備好內容，
/// 但牌組圖片得先算完才有東西可分享，所以改用這個在算完後才叫出面板。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController,
                                context: Context) {}
}

/// 讓 URL 能直接餵給 `.sheet(item:)`
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
