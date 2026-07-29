import Charts
import SwiftUI

/// 統計檢視（§4.4.4）：等級曲線、顏色圓環、判定標誌分布
struct DeckStatsView: View {
    let items: [DeckValidator.CountedCard]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryRow
                section("等級曲線") { levelChart }
                section("顏色分布") { colorDonut }
                section("判定標誌") { triggerChart }
            }
            .padding()
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("尚無資料", systemImage: "chart.bar")
            }
        }
    }

    // MARK: - 摘要卡

    private var summaryRow: some View {
        let nonClimax = items.filter { $0.card.cardType != .climax }
        let totalNonClimax = nonClimax.reduce(0) { $0 + $1.count }
        let totalCost = nonClimax.reduce(0) { $0 + ($1.card.cost ?? 0) * $1.count }
        let totalSoul = items.reduce(0) { $0 + ($1.card.soul ?? 0) * $1.count }
        let avgCost = totalNonClimax > 0
            ? String(format: "%.2f", Double(totalCost) / Double(totalNonClimax)) : "-"
        let avgPower = totalNonClimax > 0
            ? String(nonClimax.reduce(0) { $0 + ($1.card.power ?? 0) * $1.count } / totalNonClimax)
            : "-"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                   GridItem(.flexible()), GridItem(.flexible())],
                         spacing: 10) {
            statTile("總張數", "\(items.reduce(0) { $0 + $1.count })", "square.stack.3d.up")
            statTile("平均費用", avgCost, "diamond")
            statTile("平均攻擊", avgPower, "bolt")
            statTile("總魂傷", "\(totalSoul)", "flame")
        }
    }

    private func statTile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func section(_ title: String,
                         @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            chart()
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 等級曲線（漸層長條）

    private struct LevelBucket: Identifiable {
        let id: String
        let count: Int
    }

    private var levelBuckets: [LevelBucket] {
        (0...3).map { level in
            let count = items
                .filter { $0.card.level == level && $0.card.cardType != .climax }
                .reduce(0) { $0 + $1.count }
            return LevelBucket(id: "Lv\(level)", count: count)
        }
    }

    private var levelChart: some View {
        let buckets = levelBuckets
        let peak = Double(max(buckets.map(\.count).max() ?? 1, 1)) * 1.25
        let gradient = LinearGradient(colors: [.accentColor, .accentColor.opacity(0.45)],
                                      startPoint: .top, endPoint: .bottom)
        return Chart(buckets) { bucket in
            BarMark(x: .value("等級", bucket.id),
                    y: .value("張數", bucket.count),
                    width: .ratio(0.55))
                .foregroundStyle(gradient)
                .cornerRadius(6)
                .annotation(position: .top) {
                    if bucket.count > 0 {
                        Text("\(bucket.count)")
                            .font(.caption2.monospacedDigit().bold())
                    }
                }
        }
        .chartYScale(domain: 0...peak)
        .chartYAxis(.hidden)
        .frame(height: 150)
    }

    // MARK: - 顏色分布（圓環）

    private var colorDonut: some View {
        let counts = CardColor.allCases.compactMap { color -> (CardColor, Int)? in
            let count = items.filter { $0.card.color == color }.reduce(0) { $0 + $1.count }
            return count > 0 ? (color, count) : nil
        }
        let total = max(counts.reduce(0) { $0 + $1.1 }, 1)
        return HStack(spacing: 18) {
            Chart(counts, id: \.0) { color, count in
                SectorMark(angle: .value("張數", count),
                           innerRadius: .ratio(0.62),
                           angularInset: 1.5)
                    .foregroundStyle(swiftUIColor(color))
                    .cornerRadius(3)
            }
            .frame(width: 130, height: 130)
            .chartLegend(.hidden)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(counts, id: \.0) { color, count in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(swiftUIColor(color))
                            .frame(width: 10, height: 10)
                        Text(color.label).font(.caption)
                        Spacer(minLength: 6)
                        Text("\(count)")
                            .font(.caption.monospacedDigit().bold())
                        Text("\(Int(round(Double(count) / Double(total) * 100)))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - 判定標誌（含圖示）

    private var triggerChart: some View {
        let counts = TriggerIcon.allCases.compactMap { trigger -> (TriggerIcon, Int)? in
            let count = items.filter { $0.card.trigger == trigger }.reduce(0) { $0 + $1.count }
            return count > 0 ? (trigger, count) : nil
        }
        return VStack(spacing: 8) {
            if counts.isEmpty {
                Text("牌組中沒有帶判定標誌的卡")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let peak = max(counts.map(\.1).max() ?? 1, 1)
                ForEach(counts, id: \.0) { trigger, count in
                    HStack(spacing: 10) {
                        TriggerIconView(trigger: trigger, size: 18)
                            .frame(width: 26)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(.tint)
                                    .frame(width: geo.size.width
                                           * CGFloat(count) / CGFloat(peak))
                            }
                        }
                        .frame(height: 14)
                        Text("\(count)")
                            .font(.caption.monospacedDigit().bold())
                            .frame(width: 26, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func swiftUIColor(_ color: CardColor) -> Color {
        switch color {
        case .yellow: .yellow
        case .green: .green
        case .red: .red
        case .blue: .blue
        }
    }
}
