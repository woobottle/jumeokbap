import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

// MARK: - TimerPhase (Jumeokbap)
enum TimerPhase: Equatable {
    case focus, shortBreak, longBreak
}

// MARK: - TimerManager (Jumeokbap)
final class TimerManager: ObservableObject {
    private enum Keys {
        static let selectedMinutes = "jb.selectedMinutes"
        static let alarmVolume = "jb.alarmVolume"
        static let autoMute = "jb.autoMute"
        static let showFloatingDisplay = "jb.showFloatingDisplay"
        static let floatingOriginX = "jb.floatingOriginX"
        static let floatingOriginY = "jb.floatingOriginY"
        static let pomodoroEnabled = "jb.pomodoroEnabled"
        static let focusMinutes = "jb.focusMinutes"
        static let shortBreakMinutes = "jb.shortBreakMinutes"
        static let longBreakMinutes = "jb.longBreakMinutes"
        static let cyclesUntilLongBreak = "jb.cyclesUntilLongBreak"
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

    // 뽀모도로 사이클 설정 (영속)
    @Published var pomodoroEnabled = false {
        didSet { defaults.set(pomodoroEnabled, forKey: Keys.pomodoroEnabled) }
    }
    @Published var focusMinutes = 25 {
        didSet { defaults.set(focusMinutes, forKey: Keys.focusMinutes) }
    }
    @Published var shortBreakMinutes = 5 {
        didSet { defaults.set(shortBreakMinutes, forKey: Keys.shortBreakMinutes) }
    }
    @Published var longBreakMinutes = 15 {
        didSet { defaults.set(longBreakMinutes, forKey: Keys.longBreakMinutes) }
    }
    @Published var cyclesUntilLongBreak = 4 {
        didSet { defaults.set(cyclesUntilLongBreak, forKey: Keys.cyclesUntilLongBreak) }
    }

    // 뽀모도로 런타임 상태 (비영속)
    @Published var currentPhase: TimerPhase = .focus
    @Published var completedFocusSessions = 0

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
            Keys.pomodoroEnabled: false,
            Keys.focusMinutes: 25,
            Keys.shortBreakMinutes: 5,
            Keys.longBreakMinutes: 15,
            Keys.cyclesUntilLongBreak: 4,
        ])
        // 저장된 값 복원. Swift에서 프로퍼티 옵저버(didSet)는 소유 클래스의
        // init 내 대입에서는 발동하지 않으므로, register된 기본값+저장값을 읽어 대입한다.
        selectedMinutes = defaults.integer(forKey: Keys.selectedMinutes)
        alarmVolume = defaults.double(forKey: Keys.alarmVolume)
        autoMute = defaults.bool(forKey: Keys.autoMute)
        showFloatingDisplay = defaults.bool(forKey: Keys.showFloatingDisplay)
        pomodoroEnabled = defaults.bool(forKey: Keys.pomodoroEnabled)
        focusMinutes = defaults.integer(forKey: Keys.focusMinutes)
        shortBreakMinutes = defaults.integer(forKey: Keys.shortBreakMinutes)
        longBreakMinutes = defaults.integer(forKey: Keys.longBreakMinutes)
        cyclesUntilLongBreak = defaults.integer(forKey: Keys.cyclesUntilLongBreak)
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

    // 페이즈별 분
    func phaseMinutes(_ phase: TimerPhase) -> Int {
        switch phase {
        case .focus: return focusMinutes
        case .shortBreak: return shortBreakMinutes
        case .longBreak: return longBreakMinutes
        }
    }

    // 페이즈 전환 규칙 (순수 로직 — 테스트 용이)
    func nextPhase(from phase: TimerPhase, sessions: Int) -> (phase: TimerPhase, sessions: Int) {
        switch phase {
        case .focus:
            let updated = sessions + 1
            return (updated >= cyclesUntilLongBreak ? .longBreak : .shortBreak, updated)
        case .shortBreak:
            return (.focus, sessions)
        case .longBreak:
            return (.focus, 0)
        }
    }

    func start() {
        if pomodoroEnabled {
            currentPhase = .focus
            completedFocusSessions = 0
            remaining = phaseMinutes(.focus) * 60
        } else {
            remaining = selectedMinutes * 60
        }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.remaining > 0 {
                self.remaining -= 1
            } else {
                self.handlePhaseCompletion()
            }
        }
    }

    // remaining이 0에 도달했을 때: 단발은 종료, 뽀모도로는 다음 페이즈로 자동 전환
    private func handlePhaseCompletion() {
        guard pomodoroEnabled else {
            stop()
            sendNotification()
            return
        }
        sendNotification(for: currentPhase)
        let result = nextPhase(from: currentPhase, sessions: completedFocusSessions)
        currentPhase = result.phase
        completedFocusSessions = result.sessions
        remaining = phaseMinutes(currentPhase) * 60
        // 타이머는 계속 실행 (사용자가 정지할 때까지 순환)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func reset() {
        stop()
        remaining = 0
        currentPhase = .focus
        completedFocusSessions = 0
    }

    // phase가 nil이면 단발 타이머 완료 알림, 있으면 해당 페이즈 종료 알림
    func sendNotification(for phase: TimerPhase? = nil) {
        let title: String
        let body: String
        switch phase {
        case .focus:
            title = "집중 완료!"
            body = "잠깐 휴식하세요 ☕️"
        case .shortBreak, .longBreak:
            title = "휴식 끝!"
            body = "다시 집중해볼까요 🍅"
        case nil:
            title = "⏰ \(selectedMinutes)분 완료!"
            body = "휴식을 취하세요 ☕️"
        }

        // UNUserNotificationCenter를 사용하여 앱 아이콘과 함께 알림 표시
        #if os(macOS)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
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
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.deliveryDate = Date()

        // 알림 즉시 표시
        NSUserNotificationCenter.default.deliver(notification)

        // 테스트용 콜백 호출
        onNotificationSent?()
    }
}
