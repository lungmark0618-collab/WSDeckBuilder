import SwiftUI

/// 共用卡圖元件：非同步載入 + 快取 + 三種佔位狀態（§4.4.6 / §4.4.7）
struct CardImageView: View {
    let printing: Printing
    let cardName: String
    /// CX 卡為橫式卡面，用橫置比例顯示
    var landscape = false

    private enum LoadState {
        case loading
        case loaded(UIImage)
        case blockedByPolicy
        case failed
    }

    @State private var state: LoadState = .loading

    var body: some View {
        content
            .aspectRatio(landscape ? 559.0 / 400.0 : 400.0 / 559.0,
                         contentMode: .fit)  // WS 卡片比例
            .clipShape(RoundedRectangle(cornerRadius: 6))
            // 捲出畫面自動取消未完成的下載
            .task(id: printing.id) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            placeholderFrame {
                ProgressView()
            }
        case .loaded(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        case .blockedByPolicy:
            Button {
                Task { await forceLoad() }
            } label: {
                placeholderFrame {
                    VStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(.secondary)
                        Text(cardName)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Text("省流量")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(4)
                }
            }
            .buttonStyle(.plain)
        case .failed:
            Button {
                Task { await forceLoad() }
            } label: {
                placeholderFrame {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                        Text(cardName)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Text("需要連線才能載入此卡圖")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(4)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func placeholderFrame(@ViewBuilder content: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.secondarySystemBackground))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(.separator), lineWidth: 1)
            content()
        }
    }

    private func load() async {
        if case .loaded = state { return }
        state = .loading
        switch await ImageCache.shared.image(for: printing) {
        case .image(let image): state = .loaded(image)
        case .blockedByPolicy: state = .blockedByPolicy
        case .failed: state = .failed
        }
    }

    private func forceLoad() async {
        state = .loading
        switch await ImageCache.shared.forceLoad(printing) {
        case .image(let image): state = .loaded(image)
        case .blockedByPolicy: state = .blockedByPolicy
        case .failed: state = .failed
        }
    }
}
