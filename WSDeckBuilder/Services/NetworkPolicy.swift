import Foundation
import Network
import Observation

/// 行動數據控制（§4.4.7）：是否用行動數據下載卡圖，交由使用者決定
@Observable
final class NetworkPolicy {
    enum Mode: String, CaseIterable, Codable, Identifiable {
        case always          // 一律允許
        case wifiOnly        // 僅 Wi-Fi（預設）
        case wifiOnlyManual  // 僅 Wi-Fi，但可單張載入

        var id: String { rawValue }
        var label: String {
            switch self {
            case .always: "一律允許"
            case .wifiOnly: "僅 Wi-Fi"
            case .wifiOnlyManual: "僅 Wi-Fi，但可單張載入"
            }
        }
        var detail: String {
            switch self {
            case .always: "Wi-Fi 與行動數據都直接下載"
            case .wifiOnly: "行動網路下不下載，顯示佔位圖"
            case .wifiOnlyManual: "行動網路下點一下佔位圖可只載那一張"
            }
        }
    }

    static let shared = NetworkPolicy()

    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "networkMode") }
    }

    private let monitor = NWPathMonitor()
    private(set) var isExpensive = false     // 行動網路或個人熱點
    private(set) var isConstrained = false   // 系統「低數據模式」
    private(set) var isConnected = true

    /// 本月行動網路流量統計（選配功能）
    private(set) var cellularBytesThisMonth: Int64
    private var statsMonth: String

    private init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: "networkMode") ?? "")
            ?? .wifiOnly
        statsMonth = UserDefaults.standard.string(forKey: "cellularStatsMonth") ?? ""
        cellularBytesThisMonth = Int64(UserDefaults.standard.integer(forKey: "cellularBytes"))
        rolloverStatsIfNeeded()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                self.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkPolicy"))
    }

    /// 自動下載是否被允許（捲動圖鑑時）
    var allowsAutomaticDownload: Bool {
        guard isConnected else { return false }
        if isConstrained { return false }        // 尊重系統低數據模式
        if !isExpensive { return true }          // Wi-Fi 一律放行
        return mode == .always
    }

    /// 使用者主動點擊佔位圖時是否放行
    var allowsManualDownload: Bool {
        guard isConnected else { return false }
        if !isExpensive { return true }
        return mode != .wifiOnly
    }

    /// 行動網路下批次預載前必須確認（§4.4.7）
    var prefetchNeedsConfirmation: Bool { isExpensive }

    func recordDownload(bytes: Int, viaExpensivePath: Bool) {
        guard viaExpensivePath else { return }
        rolloverStatsIfNeeded()
        cellularBytesThisMonth += Int64(bytes)
        UserDefaults.standard.set(Int(cellularBytesThisMonth), forKey: "cellularBytes")
    }

    private func rolloverStatsIfNeeded() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let month = formatter.string(from: .now)
        if month != statsMonth {
            statsMonth = month
            cellularBytesThisMonth = 0
            UserDefaults.standard.set(month, forKey: "cellularStatsMonth")
            UserDefaults.standard.set(0, forKey: "cellularBytes")
        }
    }
}
