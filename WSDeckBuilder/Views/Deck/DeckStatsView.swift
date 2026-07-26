import Charts
import SwiftUI

/// 統計檢視（§4.4.4）：等級曲線、顏色分布、判定標誌分布、平均費用、總魂傷
struct DeckStatsView: View {
    let items: [DeckValidator.CountedCard]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryRow
                chartSection("等級曲線") { levelChart }
                chartSection("顏色分布") { colorChart }
                chartSection("判定標誌分布") { triggerChart }
            }
            .padding()
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("尚無資料", systemImage: "chart.bar")
            }
        }
    }

    // MARK: - 摘要

    private var summaryRow: some View {
        let nonClimax = items.filter { $0.card.cardType != .climax }
        let totalNonClimax = nonClimax.reduce(0) { $0 + $1.count }
        let totalCost = nonClimax.reduce(0) { $0 + ($1.card.cost ?? 0) * $1.count }
        let totalSoul = items.reduce(0) { $0 + ($1.card.soul ?? 0) * $1.count }
        let avgCost = totalNonClimax > 0
            ? String(format: "%.2f", Double(totalCost) / Double(totalNonClimax)) : "-"
        return HStack(spacing: 12) {
            statBox("總張數", "\(items.reduce(0) { $0 + $1.count })")
            statBox("平均費用", avgCost)
            statBox("總魂傷", "\(totalSoul)")
        }
    }

    private func statBox(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 圖表

    private func chartSection(_ title: String,
                              @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            chart()
                .frame(height: 160)
        }
    }

    private var levelChart: some View {
        let counts = (0...3).map { level in
            (level: "Lv\(level)",
             count: items.filter { $0.card.level == level && $0.card.cardType != .climax }
                 .reduce(0) { $0 + $1.count })
        }
        return Chart(counts, id: \.level) { item in
            BarMark(x: .value("等級", item.level), y: .value("張數", item.count))
                .annotation(position: .top) {
                    if item.count > 0 {
                        Text("\(item.count)").font(.caption2)
                    }
                }
        }
    }

    private var colorChart: some View {
        let counts = CardColor.allCases.map { color in
            (color: color,
             count: items.filter { $0.card.color == color }.reduce(0) { $0 + $1.count })
        }.filter { $0.count > 0 }
        return Chart(counts, id: \.color) { item in
            BarMark(x: .value("顏色", item.color.label), y: .value("張數", item.count))
                .foregroundStyle(swiftUIColor(item.color))
                .annotation(position: .top) {
                    Text("\(item.count)").font(.caption2)
                }
        }
    }

    private var triggerChart: some View {
        let counts = TriggerIcon.allCases.compactMap { trigger -> (String, Int)? in
            let count = items.filter { $0.card.trigger == trigger }.reduce(0) { $0 + $1.count }
            return count > 0 ? (trigger.label, count) : nil
        }
        return Chart(counts, id: \.0) { label, count in
            BarMark(x: .value("判定", label), y: .value("張數", count))
                .annotation(position: .top) {
                    Text("\(count)").font(.caption2)
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
