import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

// MARK: - TimerManager (Jumeokbap)
final class TimerManager: ObservableObject {
    @Published var remaining = 0 {
        didSet {
            onRemainingChanged?()
        }
    }
    @Published var isRunning = false
    var onRemainingChanged: (() -> Void)?
    @Published var selectedMinutes = 5
    @Published var alarmVolume: Double = 0.5
    @Published var autoMute = false
    @Published var compactMode = true
    @Published var showFloatingDisplay = true {
        didSet {
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
