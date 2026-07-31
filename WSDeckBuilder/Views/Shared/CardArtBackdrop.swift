import SwiftUI

/// 把卡圖放大模糊當背景，讓每副牌組帶上自己卡面的色調氛圍。
/// 只負責出圖，載入不到就靜靜留白，不顯示任何錯誤 UI（背景不該搶戲）。
struct CardArtBackdrop: View {
    let printing: Printing?
    /// 模糊強度
    var blur: CGFloat = 26
    /// 背景整體不透明度
    var opacity: Double = 0.55
    /// 模糊會把顏色洗淡，補一點飽和度才留得住卡面色調
    var saturation: Double = 1.8

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // 卡圖上半部是角色立繪，取這一段當背景最好看
                    .frame(width: geo.size.width,
                           height: geo.size.height * 2.4,
                           alignment: .top)
                    .offset(y: -geo.size.height * 0.55)
                    .blur(radius: blur, opaque: false)
                    .saturation(saturation)
                    .opacity(opacity)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // 放大取樣後圖比容器高，一定要裁在自己的邊界內，否則會蓋到相鄰的列
        .clipped()
        .allowsHitTesting(false)
        .task(id: printing?.id) { await load() }
    }

    private func load() async {
        guard let printing else { image = nil; return }
        // 只吃快取／既有政策，不強制連線——背景圖不值得為它破例下載
        if case .image(let loaded) = await ImageCache.shared.image(for: printing) {
            image = loaded
        } else {
            image = nil
        }
    }
}
