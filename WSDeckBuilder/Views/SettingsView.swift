import SwiftUI

/// 設定分頁：網路政策、快取管理、預先下載（§4.4.6 / §4.4.7）
struct SettingsView: View {
    @Environment(CardDatabase.self) private var database
    @Environment(DataUpdater.self) private var updater
    @State private var policy = NetworkPolicy.shared
    @State private var confirmRevert = false

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
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("外觀", systemImage: "paintpalette")
                    }
                } footer: {
                    Text("字體大小與粗細、文字與背景顏色、強調色。")
                }
                cardDataSection
                networkSection
                prefetchSection
                cacheSection
            }
            .navigationTitle("設定")
            .task { await refreshCacheInfo() }
        }
    }

    // MARK: - 卡表更新（§4.4.8）

    @ViewBuilder
    private var cardDataSection: some View {
        Section {
            // 每部作品各自一個版本號，改一彈就只需要下載那一份
            ForEach(database.sets.sorted { $0.titleNameZH < $1.titleNameZH },
                    id: \.titleCode) { set in
                LabeledContent(set.titleNameZH) {
                    Text("v\(set.dataVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            updateControls

            if CardDataStore.hasDownloadedData {
                Button("還原為 App 內建卡表", role: .destructive) {
                    confirmRevert = true
                }
                .confirmationDialog("下載的卡表會被刪除，改用 App 內建的版本。",
                                    isPresented: $confirmRevert,
                                    titleVisibility: .visible) {
                    Button("還原", role: .destructive) {
                        Task { await updater.revertToBundled(database: database) }
                    }
                    Button("取消", role: .cancel) {}
                }
            }
        } header: {
            Text("卡表")
        } footer: {
            cardDataFooter
        }
    }

    @ViewBuilder
    private var updateControls: some View {
        switch updater.state {
        case .checking:
            HStack { ProgressView(); Text("檢查中…").foregroundStyle(.secondary) }
        case .downloading(let done, let total):
            VStack(alignment: .leading, spacing: 6) {
                Text("更新中… \(done)/\(total)").font(.caption)
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
            }
        case .updateAvailable(let pending):
            ForEach(pending) { item in
                LabeledContent(item.titleName) {
                    Text(item.fromVersion == 0
                         ? "新作品 v\(item.toVersion)"
                         : "v\(item.fromVersion) → v\(item.toVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tint)
                }
            }
            Button {
                Task { await updater.performUpdate(pending, database: database) }
            } label: {
                Label("更新 \(pending.count) 部作品的卡表",
                      systemImage: "arrow.down.circle.fill")
            }
        default:
            Button {
                Task { await updater.check(against: database) }
            } label: {
                Label("檢查更新", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    @ViewBuilder
    private var cardDataFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch updater.state {
            case .upToDate:
                Text("已是最新版本").foregroundStyle(.green)
            case .failed(let message):
                Text(message).foregroundStyle(.orange)
            default:
                EmptyView()
            }
            if let notes = updater.notes, !notes.isEmpty {
                Text(notes)
            }
            if let checked = updater.lastCheckedAt {
                Text("上次檢查：\(checked.formatted(date: .abbreviated, time: .shortened))")
            }
            Text("更新的是卡片資料，不是 App 本身；介面與功能的變更仍須回 Xcode 重裝。"
                 + "牌組只記卡號，換卡表不影響既有牌組。")
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
