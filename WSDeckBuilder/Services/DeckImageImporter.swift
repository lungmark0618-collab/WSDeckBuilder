import CoreImage
import UIKit

/// 從匯出的牌組圖片讀回牌組：找圖上的 QR，解出載荷
enum DeckImageImporter {

    enum ImageImportError: LocalizedError {
        case noCode
        case unrecognized

        var errorDescription: String? {
            switch self {
            case .noCode:
                "這張圖裡找不到 QR。請用本 App「匯出牌組圖片」產生的圖，"
                + "或確認 QR 沒有被裁掉、遮住。"
            case .unrecognized:
                "QR 掃得到，但內容不是本 App 的牌組資料。"
            }
        }
    }

    /// 掃出圖上所有 QR 的文字內容。一張圖可能不只一個碼（例如拼圖分享）。
    ///
    /// 用 CIDetector 而非 Vision：Vision 的條碼請求要建推論環境，模擬器上會丟
    /// 「Could not create inference context」，而 QR 這種規則性圖形用 CIDetector
    /// 就夠了，也不挑執行環境。
    private static func codes(in image: UIImage) -> [String] {
        guard let ci = CIImage(image: image) else { return [] }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: ci) ?? [])
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    static func parse(image: UIImage) throws -> DeckImporter.Parsed {
        let found = codes(in: image)
        guard !found.isEmpty else { throw ImageImportError.noCode }
        for text in found {
            if let parsed = DeckImageExporter.Payload.decode(text) { return parsed }
            // QR 裡也可能直接放 JSON 或牌表文字，交給既有的解析器再試一次
            if let parsed = try? DeckImporter.parse(text) { return parsed }
        }
        throw ImageImportError.unrecognized
    }
}
