import CoreMotion
import Observation
import UIKit

/// 提供裝置傾斜角給燙金效果用（模擬實卡隨角度變色）。
/// 以引用計數啟停，沒有燙金卡在畫面上時不會耗電。
@Observable
final class MotionManager {
    static let shared = MotionManager()

    /// 左右傾斜 −1…1
    private(set) var roll: Double = 0
    /// 前後傾斜 −1…1
    private(set) var pitch: Double = 0

    private let motion = CMMotionManager()
    private var subscribers = 0

    private init() {}

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func subscribe() {
        subscribers += 1
        guard subscribers == 1, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude else { return }
            // 限制在 ±45° 內對應 −1…1，超過就飽和
            let limit = Double.pi / 4
            self.roll = max(-1, min(1, attitude.roll / limit))
            self.pitch = max(-1, min(1, (attitude.pitch - 0.6) / limit))
        }
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 {
            motion.stopDeviceMotionUpdates()
        }
    }
}
