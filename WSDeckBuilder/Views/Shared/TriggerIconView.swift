import SwiftUI

/// 觸發圖標：優先顯示官方卡面圖示，無圖示時退回文字標籤
struct TriggerIconView: View {
    let trigger: TriggerIcon
    var size: CGFloat = 18

    var body: some View {
        if let name = trigger.iconName {
            HStack(spacing: 1) {
                Image(name)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: size)
                if trigger == .soul2 {
                    Image(name)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: size)
                }
            }
        } else {
            Text(trigger.label).font(.callout.bold())
        }
    }
}

/// 能力文字內嵌圖示：把【城門】【木門】【開機】【箭頭】【寶】【本】等
/// 標記換成卡片上的圖示（日文的【門】【扉】【待】【選】也一併對應）
enum CardTextRenderer {

    private static let markerIcons: [(String, String)] = [
        ("【雙魂】", "trigger_soul"),   // 先比對長字串避免誤切
        ("【箭頭】", "trigger_focus"),
        ("【開機】", "trigger_standby"),
        ("【木門】", "trigger_salvage"),
        ("【城門】", "trigger_gate"),
        ("【寶】", "trigger_treasure"),
        ("【本】", "trigger_draw"),
        ("【魂】", "trigger_soul"),
        ("【槍】", "trigger_shot"),
        ("【選】", "trigger_focus"),
        ("【待】", "trigger_standby"),
        ("【扉】", "trigger_salvage"),
        ("【門】", "trigger_gate"),
    ]

    static func render(_ line: String) -> Text {
        var result = Text(verbatim: "")
        var rest = Substring(line)
        while !rest.isEmpty {
            // 找出最先出現的標記
            var earliest: (range: Range<Substring.Index>, icon: String)?
            for (marker, icon) in markerIcons {
                if let range = rest.range(of: marker),
                   earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                    earliest = (range, icon)
                }
            }
            guard let match = earliest else {
                result = result + Text(String(rest))
                break
            }
            result = result + Text(String(rest[..<match.range.lowerBound]))
            result = result + Text(Image(match.icon)).baselineOffset(-2)
            rest = rest[match.range.upperBound...]
        }
        return result
    }
}
