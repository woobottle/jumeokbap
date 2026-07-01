import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

// MARK: - TimerManager (Jumeokbap)
final class TimerManager: ObservableObject {
    private enum Keys {
        static let selectedMinutes = "jb.selectedMinutes"
        static let alarmVolume = "jb.alarmVolume"
        static let autoMute = "jb.autoMute"
        static let showFloatingDisplay = "jb.showFloatingDisplay"
        static let floatingOriginX = "jb.floatingOriginX"
        static let floatingOriginY = "jb.floatingOriginY"
    }

    private let defaults: UserDefaults

    @Published var remaining = 0 {
        didSet {
            onRemainingChanged?()
        }
    }
    @Published var isRunning = false
    var onRemainingChanged: (() -> Void)?
    @Published var selectedMinutes = 5 {
        didSet { defaults.set(selectedMinutes, forKey: Keys.selectedMinutes) }
    }
    @Published var alarmVolume: Double = 0.5 {
        didSet { defaults.set(alarmVolume, forKey: Keys.alarmVolume) }
    }
    @Published var autoMute = false {
        didSet { defaults.set(autoMute, forKey: Keys.autoMute) }
    }
    @Published var showFloatingDisplay = true {
        didSet {
            defaults.set(showFloatingDisplay, forKey: Keys.showFloatingDisplay)
            onFloatingDisplayChanged?(showFloatingDisplay)
        }
    }
    var onFloatingDisplayChanged: ((Bool) -> Void)?
    var onDragWindow: ((CGSize) -> Void)?
    var onDragStart: (() -> Void)? = nil
    var onDragEnd: ((CGSize) -> Void)? = nil
    var onNotificationSent: (() -> Void)? // 테스트용 알림 전송 콜백
    var appIconImage: NSImage?
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.selectedMinutes: 5,
            Keys.alarmVolume: 0.5,
            Keys.autoMute: false,
            Keys.showFloatingDisplay: true,
        ])
        // 저장된 값 복원. Swift에서 프로퍼티 옵저버(didSet)는 소유 클래스의
        // init 내 대입에서는 발동하지 않으므로, register된 기본값+저장값을 읽어 대입한다.
        selectedMinutes = defaults.integer(forKey: Keys.selectedMinutes)
        alarmVolume = defaults.double(forKey: Keys.alarmVolume)
        autoMute = defaults.bool(forKey: Keys.autoMute)
        showFloatingDisplay = defaults.bool(forKey: Keys.showFloatingDisplay)
    }

    var savedFloatingOrigin: CGPoint? {
        guard defaults.object(forKey: Keys.floatingOriginX) != nil,
              defaults.object(forKey: Keys.floatingOriginY) != nil else { return nil }
        return CGPoint(x: defaults.double(forKey: Keys.floatingOriginX),
                       y: defaults.double(forKey: Keys.floatingOriginY))
    }

    func saveFloatingOrigin(_ point: CGPoint) {
        defaults.set(Double(point.x), forKey: Keys.floatingOriginX)
        defaults.set(Double(point.y), forKey: Keys.floatingOriginY)
    }

    var formattedTime: String {
        String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    func start() {
        remaining = selectedMinutes * 60
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.remaining > 0 {
                self.remaining -= 1
            } else {
                self.stop()
                self.sendNotification()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func reset() {
        stop()
        remaining = 0
    }

    func sendNotification() {
        // UNUserNotificationCenter를 사용하여 앱 아이콘과 함께 알림 표시
        #if os(macOS)
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(selectedMinutes)분 완료!"
        content.body = "휴식을 취하세요 ☕️"
        content.sound = UNNotificationSound.default

        // 알림 요청 생성 및 전송
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("UNUserNotification 전송 실패: \(error.localizedDescription)")
            }
        }
        #endif

        // NSUserNotification도 함께 사용 (호환성 유지)
        let notification = NSUserNotification()
        notification.title = "⏰ \(selectedMinutes)분 완료!"
        notification.informativeText = "휴식을 취하세요 ☕️"
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.deliveryDate = Date()

        // 알림 즉시 표시
        NSUserNotificationCenter.default.deliver(notification)

        // 테스트용 콜백 호출
        onNotificationSent?()
    }
}
