import Foundation
import Observation

/// 下載回來的卡表放哪。用 Application Support 而非 Caches——
/// Caches 在裝置空間不足時會被系統清掉，卡表被清掉就退回內建的舊版了。
enum CardDataStore {
    static var directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("CardData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        // 卡表公開發佈後隨時能重抓，沒必要佔使用者的 iCloud 備份容量。
        // （卡圖快取也是同樣理由排除備份。）
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    static func file(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// 還原成內建版本：把下載的檔案全部刪掉
    static func removeAll() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        for file in files where file.lastPathComponent.hasSuffix("_cards.json") {
            try FileManager.default.removeItem(at: file)
        }
    }

    static var hasDownloadedData: Bool {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.lastPathComponent.hasSuffix("_cards.json") }
    }
}

// MARK: - 線上目錄

/// `manifest.json` 的結構。只記版本與網址，本身很小，查更新時只下載這個。
struct UpdateManifest: Decodable {
    let schemaVersion: Int
    let updatedAt: String?
    let notes: String?
    let sets: [SetEntry]

    struct SetEntry: Decodable {
        let titleCode: String
        /// 要寫成哪個本機檔名，必須對得上 Bundle 內的檔名才蓋得掉內建版
        let file: String
        let dataVersion: Int
        /// 可以是絕對網址，也可以是相對於 manifest 的路徑
        let url: String

        enum CodingKeys: String, CodingKey {
            case titleCode = "title_code"
            case file
            case dataVersion = "data_version"
            case url
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case notes
        case sets
    }
}

// MARK: - 更新器

/// 卡表線上更新（§4.4.8）。更新的是**資料**不是程式：
/// iOS 禁止 App 下載並執行新程式碼，介面與功能的變更仍須回 Xcode 重裝。
///
/// 之所以幾乎免費，是因為 `DeckEntry` 只存卡號不存卡片內容——
/// 整份卡表換掉後既有牌組自動套用新資料，不需要任何遷移。
@Observable
@MainActor
final class DataUpdater {
    /// 這版 App 看得懂的 manifest 格式
    static let supportedSchemaVersion = 1

    /// 卡表發佈位置（§6.3：v1.8 起改為 public GitHub repo）。
    ///
    /// 用 raw.githubusercontent.com 而非 github.com/…/blob/…——後者回傳的是 HTML 不是 JSON。
    /// raw 走 Fastly CDN、約快取 5 分鐘，所以 push 後可能要等幾分鐘才查得到新版，不是壞掉。
    static let manifestURL = URL(string: "https://raw.githubusercontent.com"
        + "/lungmark0618-collab/WSDeckBuilder/main/data/manifest.json")!

    enum State: Equatable {
        case idle
        case checking
        /// 有幾部作品可以更新
        case updateAvailable([Pending])
        case downloading(done: Int, total: Int)
        case upToDate
        case failed(String)
    }

    /// 一部要更新的作品
    struct Pending: Equatable, Identifiable {
        let titleCode: String
        let titleName: String
        let file: String
        let url: URL
        let fromVersion: Int
        let toVersion: Int
        var id: String { titleCode }
    }

    private(set) var state: State = .idle
    private(set) var notes: String?

    private static let checkedKey = "cardDataLastCheckedAt"

    /// 存起來，「一天查一次」才能跨越重開 App
    var lastCheckedAt: Date? {
        didSet {
            UserDefaults.standard.set(lastCheckedAt?.timeIntervalSince1970,
                                      forKey: Self.checkedKey)
        }
    }

    init() {
        let stamp = UserDefaults.standard.double(forKey: Self.checkedKey)
        lastCheckedAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    // MARK: - 檢查

    /// 啟動時靜默呼叫。查不到就沿用本地資料，不跳錯誤打擾（§4.4.8）
    func checkSilently(against database: CardDatabase) async {
        // 一天查一次就夠，不必每次開 App 都連線
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < 86_400 { return }
        guard NetworkPolicy.shared.allowsAutomaticDownload else { return }
        await check(against: database, silent: true)
    }

    func check(against database: CardDatabase, silent: Bool = false) async {
        if !silent { state = .checking }
        do {
            var request = URLRequest(url: Self.manifestURL)
            // manifest 一定要拿最新的，不然改了版本號 App 還在讀舊的快取
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response)
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            guard manifest.schemaVersion <= Self.supportedSchemaVersion else {
                // 舊程式硬讀新格式會崩，寧可要求更新 App
                state = .failed("卡表格式為第 \(manifest.schemaVersion) 版，"
                                + "這個 App 只看得懂第 \(Self.supportedSchemaVersion) 版。"
                                + "請回 Xcode 更新 App 本身。")
                return
            }
            lastCheckedAt = Date()
            notes = manifest.notes
            let pending = Self.pending(in: manifest, base: Self.manifestURL,
                                       database: database)
            state = pending.isEmpty ? .upToDate : .updateAvailable(pending)
        } catch {
            // 靜默檢查失敗就當作沒事發生，不要在開場擋人
            state = silent ? .idle : .failed(Self.message(for: error))
        }
    }

    /// 線上版本比本地新的才算——本地版本直接讀已載入的卡表，
    /// 不另外記一份，免得兩邊對不上
    private static func pending(in manifest: UpdateManifest, base: URL,
                                database: CardDatabase) -> [Pending] {
        manifest.sets.compactMap { entry in
            guard entry.file.hasSuffix("_cards.json") else { return nil }
            guard let url = URL(string: entry.url, relativeTo: base) else { return nil }
            let local = database.sets.first { $0.titleCode == entry.titleCode }
            // 本地沒有的作品也算更新——這就是新彈進來的方式
            let current = local?.dataVersion ?? 0
            guard entry.dataVersion > current else { return nil }
            return Pending(titleCode: entry.titleCode,
                           titleName: local?.titleNameZH ?? entry.titleCode,
                           file: entry.file,
                           url: url.absoluteURL,
                           fromVersion: current,
                           toVersion: entry.dataVersion)
        }
    }

    // MARK: - 下載與替換

    /// 使用者確認後才下載。原子性替換：先寫暫存檔、驗證解得開，再一次換掉；
    /// 中途失敗不影響現有資料
    func performUpdate(_ pending: [Pending], database: CardDatabase) async {
        guard !pending.isEmpty else { return }
        // 連點兩下「更新」會重複下載並互相覆寫。畫面上按鈕在下載時就換成進度條了，
        // 但那是畫面層的保護，狀態自己也要擋。
        if case .downloading = state { return }
        state = .downloading(done: 0, total: pending.count)
        var installed = 0
        for item in pending {
            do {
                try await install(item)
                installed += 1
                state = .downloading(done: installed, total: pending.count)
            } catch {
                // 已經裝好的留著，只回報停在哪裡
                if installed > 0 { await database.reload() }
                state = .failed("\(item.titleName)：\(Self.message(for: error))")
                return
            }
        }
        await database.reload()
        state = .upToDate
    }

    private func install(_ item: Pending) async throws {
        var request = URLRequest(url: item.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        NetworkPolicy.shared.recordDownload(
            bytes: data.count, viaExpensivePath: NetworkPolicy.shared.isExpensive)

        // 先確定這份資料解得開再落地，否則會把好的卡表換成壞的
        let decoded = try JSONDecoder().decode(CardSet.self, from: data)
        guard decoded.meta.titleCode == item.titleCode else {
            throw UpdateError.mismatchedTitle(expected: item.titleCode,
                                              got: decoded.meta.titleCode)
        }
        guard !decoded.cards.isEmpty else { throw UpdateError.emptySet }

        let target = CardDataStore.file(named: item.file)
        let temp = CardDataStore.directory
            .appendingPathComponent("\(item.file).download")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: target)
        }
    }

    /// 還原成 App 內建的卡表
    func revertToBundled(database: CardDatabase) async {
        do {
            try CardDataStore.removeAll()
            await database.reload()
            state = .idle
            notes = nil
            lastCheckedAt = nil
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    // MARK: - 錯誤

    enum UpdateError: LocalizedError {
        case badStatus(Int)
        case mismatchedTitle(expected: String, got: String)
        case emptySet

        var errorDescription: String? {
            switch self {
            case .badStatus(let code):
                "伺服器回應 \(code)"
            case .mismatchedTitle(let expected, let got):
                "作品代號對不上（預期 \(expected)，拿到 \(got)）"
            case .emptySet:
                "這份卡表沒有任何卡片"
            }
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.badStatus(http.statusCode)
        }
    }

    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        if error is DecodingError {
            return "檔案格式不正確，無法解析"
        }
        return error.localizedDescription
    }
}
