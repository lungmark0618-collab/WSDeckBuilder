import SwiftUI

/// 篩選條件 sheet（§4.4.1：條件間 AND、同條件內 OR）
struct FilterSheet: View {
    @Binding var query: SearchQuery
    @Environment(CardDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("等級") {
                    toggleRow(items: [0, 1, 2, 3], set: $query.levels) { "Lv\($0)" }
                }
                Section("顏色") {
                    toggleRow(items: CardColor.allCases, set: $query.colors) { $0.label }
                }
                Section("種類") {
                    toggleRow(items: CardType.allCases, set: $query.types) { $0.label }
                }
                Section("判定標誌") {
                    toggleRow(items: TriggerIcon.allCases, set: $query.triggers) { $0.label }
                }
                Section("特徵") {
                    toggleRow(items: database.allTraits, set: $query.traits) { "《\($0)》" }
                }
                Section("收錄來源") {
                    Picker("來源", selection: $query.sourceOnly) {
                        Text("全部").tag(CardSource?.none)
                        ForEach(CardSource.allCases) { source in
                            Text(source.label).tag(CardSource?.some(source))
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("篩選")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("全部清除") {
                        let keyword = query.keyword
                        query = SearchQuery(keyword: keyword)
                    }
                    .disabled(!query.hasActiveFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 橫向 chip 多選列
    private func toggleRow<T: Hashable>(items: [T],
                                        set: Binding<Set<T>>,
                                        label: @escaping (T) -> String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let isOn = set.wrappedValue.contains(item)
                    Button {
                        if isOn {
                            set.wrappedValue.remove(item)
                        } else {
                            set.wrappedValue.insert(item)
                        }
                    } label: {
                        Text(label(item))
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isOn ? Color.accentColor : Color(.tertiarySystemFill),
                                        in: Capsule())
                            .foregroundStyle(isOn ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
