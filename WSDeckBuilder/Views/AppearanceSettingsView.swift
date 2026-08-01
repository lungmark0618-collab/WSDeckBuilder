import SwiftUI

/// 外觀個人化設定：字體、顏色、背景、強調色，附即時預覽
struct AppearanceSettingsView: View {
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(CardDatabase.self) private var database

    var body: some View {
        @Bindable var settings = appearance
        Form {
            Section("預覽") { previewCard }

            Section {
                Toggle("同時顯示日文原文", isOn: $settings.showJapanese)
            } header: {
                Text("語言")
            } footer: {
                Text("關閉後卡片詳情只留繁中；卡片詳情右上角也可以隨時切換。"
                     + "《》內的特徵沒有官方中譯，一律保留日文。")
            }

            Section("字體") {
                Picker("字級", selection: $settings.textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("字重", selection: $settings.textWeight) {
                    ForEach(TextWeight.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("文字顏色") {
                Picker("文字顏色", selection: $settings.textTone) {
                    ForEach(TextTone.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                Picker("背景", selection: $settings.background) {
                    ForEach(BackgroundStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("背景")
            } footer: {
                Text("「純黑」在 OLED 螢幕上最省電；「米紙」是護眼的暖色底。")
            }

            Section {
                Picker("強調色", selection: $settings.accentMode) {
                    ForEach(AccentMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settings.accentMode == .fixed {
                    colorSwatches
                } else {
                    titlePaletteRow
                }
            } header: {
                Text("強調色")
            } footer: {
                Text(settings.accentMode == .followTitle
                     ? "在圖鑑切換作品時，App 的強調色會跟著該作品變化。"
                     : "所有畫面統一使用選定的顏色。")
            }

            Section {
                Button("回復預設值", role: .destructive) { resetAll() }
            }
        }
        .navigationTitle("外觀")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 預覽

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("海灘天使 泰蕾莎").font(.headline)
                Spacer()
                Text("×4").font(.body.monospacedDigit().bold())
                    .foregroundStyle(appearance.accentColor)
            }
            Text("BRD/W139-075　Lv0／費0／1000／魂1")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("【自】 此卡從手牌被放置到舞台時，你可以支付費用。")
                .font(.callout)
            HStack(spacing: 8) {
                ForEach(["角色", "黃", "RR"], id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(appearance.accentColor.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 顏色選擇

    private var colorSwatches: some View {
        @Bindable var settings = appearance
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AccentPreset.allCases) { preset in
                    Button {
                        settings.fixedAccent = preset
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if settings.fixedAccent == preset {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            Text(preset.label).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 顯示各作品對應的顏色，讓使用者知道會怎麼變
    private var titlePaletteRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(database.sets, id: \.titleCode) { meta in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(TitlePalette.accent(for: meta.titleCode))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if meta.titleCode == appearance.currentTitleCode {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        Text(meta.titleNameZH)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: 64)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func resetAll() {
        appearance.showJapanese = false
        appearance.textSize = .standard
        appearance.textWeight = .regular
        appearance.textTone = .standard
        appearance.background = .system
        appearance.accentMode = .followTitle
        appearance.fixedAccent = .rose
    }
}
