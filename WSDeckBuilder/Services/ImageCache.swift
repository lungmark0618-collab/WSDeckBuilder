import Foundation
import UIKit

/// 記憶體 + 磁碟兩層快取（§4.4.6）。目標：第一次看過的卡圖，之後永遠不用再下載。
actor ImageCache {
    static let shared = ImageCache()

    enum LoadResult {
        case image(UIImage)
        case blockedByPolicy    // 因網路政策未下載（可點擊載入）
        case failed             // 下載失敗（可重試）
    }

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    /// 同一張圖同時被多個 View 請求時只發一次下載
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// 行動網路下選「僅用 Wi-Fi 時下載」的預載佇列
    private var pendingPrefetch: [Printing] = []

    /// 網格顯示用的降採樣上限（點數 × scale 足夠 2~3 欄網格與詳情大圖共用）
    static let gridPixelSize: CGFloat = 800

    private init() {
        // 用 Application Support 而非 Caches：Caches 會被系統清除（§4.4.6）
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("CardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // ⚠ iOS 必做：排除 iCloud 備份（圖片可重新下載，不佔備份容量）
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)

        // 記憶體上限 40 MB（iOS 記憶體吃緊，§4.4.6 建議 30~50 MB）
        memory.totalCostLimit = 40 * 1024 * 1024
    }

    /// 收到記憶體警告時清空記憶體快取（磁碟保留）
    func handleMemoryWarning() {
        memory.removeAllObjects()
    }

    // MARK: - 載入

    /// 一般載入（受網路政策約束，捲動時呼叫）
    func image(for printing: Printing) async -> LoadResult {
        if let cached = cachedImage(for: printing) { return .image(cached) }
        guard await NetworkPolicy.shared.allowsAutomaticDownload else {
            return .blockedByPolicy
        }
        if let image = await download(printing) { return .image(image) }
        return .failed
    }

    /// 使用者主動點擊佔位圖，單張強制載入（§4.4.7 單張例外）
    func forceLoad(_ printing: Printing) async -> LoadResult {
        if let cached = cachedImage(for: printing) { return .image(cached) }
        guard await NetworkPolicy.shared.allowsManualDownload else {
            return .blockedByPolicy
        }
        if let image = await download(printing) { return .image(image) }
        return .failed
    }

    /// 只取已經在本機的圖，不連網。出牌組圖片時用——出圖不該卡在下載上，
    /// 沒快取到的卡就畫佔位。
    func cachedOnly(_ printings: [Printing]) -> [String: UIImage] {
        var out: [String: UIImage] = [:]
        for printing in printings {
            if let image = cachedImage(for: printing) { out[printing.id] = image }
        }
        return out
    }

    private func cachedImage(for printing: Printing) -> UIImage? {
        let key = printing.id as NSString
        if let image = memory.object(forKey: key) { return image }
        let file = directory.appendingPathComponent(printing.cacheFileName)
        guard let data = try? Data(contentsOf: file),
              let image = ImageDownsampler.downsample(data: data,
                                                      maxPixelSize: Self.gridPixelSize)
        else { return nil }
        memory.setObject(image, forKey: key, cost: data.count)
        return image
    }

    private func download(_ printing: Printing) async -> UIImage? {
        if let task = inFlight[printing.id] {
            return await task.value
        }
        let task = Task<UIImage?, Never> { [directory] in
            var request = URLRequest(url: printing.imageURL)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
                             forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  !data.isEmpty else { return nil }
            let file = directory.appendingPathComponent(printing.cacheFileName)
            try? data.write(to: file, options: .atomic)
            await NetworkPolicy.shared.recordDownload(
                bytes: data.count,
                viaExpensivePath: NetworkPolicy.shared.isExpensive)
            return ImageDownsampler.downsample(data: data, maxPixelSize: Self.gridPixelSize)
        }
        inFlight[printing.id] = task
        let image = await task.value
        inFlight[printing.id] = nil
        if let image {
            memory.setObject(image, forKey: printing.id as NSString,
                             cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        }
        return image
    }

    // MARK: - 批次預先下載（設定頁）

    /// 併發上限 4，逐張回報進度
    func prefetch(_ printings: [Printing],
                  progress: @escaping @Sendable (Int, Int) -> Void) async {
        let missing = printings.filter {
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent($0.cacheFileName).path)
        }
        let total = missing.count
        var done = 0
        var iterator = missing.makeIterator()
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<4 {
                if let printing = iterator.next() {
                    group.addTask { await self.download(printing) != nil }
                }
            }
            while await group.next() != nil {
                done += 1
                progress(done, total)
                // 中途切到行動網路則暫停，排入佇列等 Wi-Fi
                guard await NetworkPolicy.shared.allowsAutomaticDownload else {
                    var remaining: [Printing] = []
                    while let printing = iterator.next() { remaining.append(printing) }
                    pendingPrefetch = remaining
                    group.cancelAll()
                    break
                }
                if let printing = iterator.next() {
                    group.addTask { await self.download(printing) != nil }
                }
            }
        }
    }

    /// 連回 Wi-Fi 時繼續佇列中的預載
    func resumePendingPrefetchIfAny(progress: @escaping @Sendable (Int, Int) -> Void) async {
        guard !pendingPrefetch.isEmpty,
              await NetworkPolicy.shared.allowsAutomaticDownload else { return }
        let queued = pendingPrefetch
        pendingPrefetch = []
        await prefetch(queued, progress: progress)
    }

    func queuePrefetchForWiFi(_ printings: [Printing]) {
        pendingPrefetch = printings
    }

    // MARK: - 快取管理

    func cacheSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    func cachedCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    func clearCache() {
        memory.removeAllObjects()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
