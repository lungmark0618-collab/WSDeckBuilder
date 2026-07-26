import SwiftUI

/// 設定分頁：網路政策、快取管理、預先下載（§4.4.6 / §4.4.7）
struct SettingsView: View {
    @Environment(CardDatabase.self) private var database
    @State private var policy = NetworkPolicy.shared

    @State private var cacheSize: Int64 = 0
    @State private var cachedCount = 0
    @State private var prefetchProgress: (done: Int, total: Int)?
    @State private var confirmPrefetch: PrefetchScope?
    @State private var confirmClear = false

    enum PrefetchScope: String, Identifiable {
        case normalOnly, allPrintings
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                networkSection
                prefetchSection
                cacheSection
                aboutSection
            }
            .navigationTitle("設定")
            .task { await refreshCacheInfo() }
        }
    }

    // MARK: - 網路政策

    private var networkSection: some View {
        Section {
            Picker("卡圖下載", selection: Binding(
                get: { policy.mode },
                set: { policy.mode = $0 })) {
                ForEach(NetworkPolicy.Mode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("網路使用政策")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(policy.mode.detail)
                if policy.isConstrained {
                    Text("目前系統為低數據模式，自動下載已暫停")
                        .foregroundStyle(.orange)
                }
                let bytes = policy.cellularBytesThisMonth
                if bytes > 0 {
                    Text("本月經由行動網路下載：\(formatBytes(bytes))")
                }
            }
        }
    }

    // MARK: - 預先下載（§4.4.6）

    private var prefetchSection: some View {
        Section {
            if let progress = prefetchProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("下載中… \(progress.done)/\(progress.total)")
                        .font(.caption)
                    ProgressView(value: progress.total > 0
                                 ? Double(progress.done) / Double(progress.total) : 0)
                }
            } else {
                Button {
                    requestPrefetch(.normalOnly)
                } label: {
                    Label("預先下載卡圖（僅普卡，約 \(database.cards.count) 張）",
                          systemImage: "arrow.down.circle")
                }
                Button {
                    requestPrefetch(.allPrintings)
                } label: {
                    Label("預先下載卡圖（含全部刷版，約 \(allPrintings.count) 張）",
                          systemImage: "arrow.down.circle.dotted")
                }
            }
        } header: {
            Text("預先下載")
        } footer: {
            Text("建議出門前先在家用 Wi-Fi 下載完成，牌店現場網路不好時仍能看圖。")
        }
        .confirmationDialog(
            "目前使用行動網路\n預先下載將消耗約 \(estimateSize(for: confirmPrefetch)) 流量",
            isPresented: .init(get: { confirmPrefetch != nil },
                               set: { if !$0 { confirmPrefetch = nil } }),
            titleVisibility: .visible) {
            Button("仍要下載") {
                if let scope = confirmPrefetch { startPrefetch(scope) }
            }
            Button("僅用 Wi-Fi 時下載") {
                if let scope = confirmPrefetch {
                    Task { await ImageCache.shared.queuePrefetchForWiFi(printings(for: scope)) }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 快取管理

    private var cacheSection: some View {
        Section {
            LabeledContent("已快取卡圖", value: "\(cachedCount) 張")
            LabeledContent("快取容量", value: formatBytes(cacheSize))
            Button("清除圖片快取", role: .destructive) {
                confirmClear = true
            }
            .confirmationDialog("確定要清除全部卡圖快取嗎？之後需要重新下載。",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除", role: .destructive) {
                    Task {
                        await ImageCache.shared.clearCache()
                        await refreshCacheInfo()
                    }
                }
                Button("取消", role: .cancel) {}
            }
        } header: {
            Text("圖片快取")
        } footer: {
            Text("卡圖存於本機（不佔 iCloud 備份），看過一次即永久保留。")
        }
    }

    private var aboutSection: some View {
        Section("關於") {
            LabeledContent("收錄作品", value: database.meta?.titleNameZH ?? "-")
            LabeledContent("作品編號", value: database.meta?.titleCode ?? "-")
            LabeledContent("卡片數", value: "\(database.cards.count) 張")
            LabeledContent("翻譯狀態",
                           value: "機器翻譯（待校對）")
        }
    }

    // MARK: - Helpers

    private var allPrintings: [Printing] {
        database.cards.flatMap(\.printings)
    }

    private func printings(for scope: PrefetchScope) -> [Printing] {
        switch scope {
        case .normalOnly: database.cards.map(\.defaultPrinting)
        case .allPrintings: allPrintings
        }
    }

    private func estimateSize(for scope: PrefetchScope?) -> String {
        let count = scope.map { printings(for: $0).count } ?? 0
        return formatBytes(Int64(count) * 110 * 1024)  // 單張約 110 KB 估算
    }

    private func requestPrefetch(_ scope: PrefetchScope) {
        // 不論政策設定為何，行動網路下批次預載都要確認（§4.4.7）
        if policy.prefetchNeedsConfirmation {
            confirmPrefetch = scope
        } else {
            startPrefetch(scope)
        }
    }

    private func startPrefetch(_ scope: PrefetchScope) {
        let targets = printings(for: scope)
        prefetchProgress = (0, targets.count)
        Task {
            await ImageCache.shared.prefetch(targets) { done, total in
                Task { @MainActor in
                    prefetchProgress = (done, total)
                }
            }
            prefetchProgress = nil
            await refreshCacheInfo()
        }
    }

    private func refreshCacheInfo() async {
        cacheSize = await ImageCache.shared.cacheSize()
        cachedCount = await ImageCache.shared.cachedCount()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
