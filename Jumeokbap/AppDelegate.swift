import SwiftUI
import Swift
import SwiftData
import UserNotifications


// MARK: - AppDelegate (Jumeokbap)
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var floatingWindow: NSWindow?
    let timerManager = TimerManager()
    private var initialWindowOrigin: CGPoint?
    private var lastDragLocation: CGPoint?
    private var dragOffsetFromMouse: CGPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupPopover()
        setupFloatingTimer()
        setupFloatingDisplayObserver()
        setupAppIcon()
        requestNotificationPermission()
    }

    // 메뉴바 아이템
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarTitle()

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // TimerManager의 remaining 변경을 관찰해서 메뉴 바 업데이트
        timerManager.onRemainingChanged = { [weak self] in
            self?.updateStatusBarTitle()
        }
    }

    func updateStatusBarTitle() {
        statusItem.button?.title = timerManager.isRunning
            ? timerManager.formattedTime
            : "주먹밥"
    }

    // 팝오버 (설정창)
    func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 280)
        popover.contentViewController = NSHostingController(rootView: SettingsView(timerManager: timerManager))
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    // 항상 위 플로팅 타이머
    func setupFloatingTimer() {
        let view = FloatingTimerView(timerManager: timerManager)
        let hosting = NSHostingView(rootView: view)
        // 초기 위치를 화면 우측 상단으로 배치
        let windowSize = NSSize(width: 120, height: 60)
        let margin: CGFloat = 12
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let originX = visible.maxX - windowSize.width - margin
        let originY = visible.maxY - windowSize.height - margin
        let initialRect = NSRect(x: originX, y: originY, width: windowSize.width, height: windowSize.height)

        floatingWindow = NSWindow(
            contentRect: initialRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        floatingWindow?.contentView = hosting
        floatingWindow?.isOpaque = false
        floatingWindow?.backgroundColor = .clear
        floatingWindow?.level = .floating
        if timerManager.showFloatingDisplay {
            floatingWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func setupFloatingDisplayObserver() {
        timerManager.onFloatingDisplayChanged = { [weak self] show in
            self?.toggleFloatingDisplay(show)
        }

        timerManager.onDragStart = { [weak self] in
            self?.prepareDragForMouseFollow()
        }

        timerManager.onDragWindow = { [weak self] _ in
            self?.followMouse()
        }

        timerManager.onDragEnd = { [weak self] _ in
            self?.finishDrag()
        }
    }

    func saveInitialWindowPosition() {
        initialWindowOrigin = floatingWindow?.frame.origin
        lastDragLocation = nil // 드래그 시작 시 리셋
    }

    func moveFloatingWindow(by translation: CGSize) {
        // 기존 상대 이동 방식(호환용) — 절대 마우스 추적을 우선 사용
        guard let window = floatingWindow, let initialOrigin = initialWindowOrigin else { return }
        var frame = window.frame
        frame.origin.x = initialOrigin.x + translation.width
        frame.origin.y = initialOrigin.y - translation.height
        window.setFrame(frame, display: false)
    }

    // 절대 마우스 위치를 따라다니도록 준비: 마우스와 창 원점 간 오프셋 저장
    func prepareDragForMouseFollow() {
        guard let window = floatingWindow else { return }
        initialWindowOrigin = window.frame.origin
        let mouse = NSEvent.mouseLocation
        dragOffsetFromMouse = CGPoint(x: mouse.x - window.frame.origin.x, y: mouse.y - window.frame.origin.y)
    }

    // 드래그 중 마우스를 지속적으로 따라다님
    func followMouse() {
        guard let window = floatingWindow, let offset = dragOffsetFromMouse else { return }
        let mouse = NSEvent.mouseLocation
        var frame = window.frame
        frame.origin.x = mouse.x - offset.x
        frame.origin.y = mouse.y - offset.y
        window.setFrame(frame, display: false)
    }

    // 드래그 종료 시 화면 가장자리 스냅 + 화면 내부로 클램프
    func finishDrag() {
        guard let window = floatingWindow, let screen = NSScreen.main else { return }

        var frame = window.frame

        // 화면 작업 영역
        let visible = screen.visibleFrame

        // 클램프: 창이 화면 밖으로 나가지 않도록 제한
        let minX = visible.minX
        let maxX = visible.maxX - frame.size.width
        let minY = visible.minY
        let maxY = visible.maxY - frame.size.height
        frame.origin.x = max(minX, min(maxX, frame.origin.x))
        frame.origin.y = max(minY, min(maxY, frame.origin.y))

        // 스냅: 좌/우 가장자리로 스냅 (여백 12)
        let snapMargin: CGFloat = 12
        let distanceToLeft = abs(frame.origin.x - minX)
        let distanceToRight = abs(maxX - frame.origin.x)
        if min(distanceToLeft, distanceToRight) < 80 { // 80px 이내면 스냅
            if distanceToLeft < distanceToRight {
                frame.origin.x = minX + snapMargin
            } else {
                frame.origin.x = maxX - snapMargin
            }
        }

        window.setFrame(frame, display: true, animate: true)
        // 드래그 종료 후 기준점 업데이트
        initialWindowOrigin = frame.origin
        dragOffsetFromMouse = nil
    }

    func toggleFloatingDisplay(_ show: Bool) {
        if show {
            floatingWindow?.makeKeyAndOrderFront(nil)
        } else {
            floatingWindow?.orderOut(nil)
        }
    }

    func requestNotificationPermission() {
        // UNUserNotificationCenter 권한 요청 및 델리게이트 설정
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("UNUserNotificationCenter 권한 요청 실패: \(error.localizedDescription)")
            } else if granted {
                print("UNUserNotificationCenter 권한 승인됨")
            } else {
                print("UNUserNotificationCenter 권한 거부됨")
            }
        }

        // NSUserNotificationCenter 설정 (macOS에서 더 확실한 알림 표시를 위해)
        NSUserNotificationCenter.default.delegate = self

        // 앱이 포그라운드에 있을 때도 알림 표시되도록 설정
        DispatchQueue.main.async {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

    func setupAppIcon() {
        // 앱 아이콘을 TimerManager에 설정 (알림에 표시하기 위해)
        timerManager.appIconImage = NSApp?.applicationIconImage
    }

    // MARK: - NSUserNotificationCenterDelegate

    func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        print("알림이 성공적으로 전달됨: \(notification.title ?? "")")
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        print("알림이 클릭됨: \(notification.title ?? "")")
        // 알림 클릭 시 앱을 활성화
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        // 앱이 포그라운드에 있을 때도 알림 표시
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 앱이 포그라운드에 있을 때도 알림 표시 및 소리 재생
        completionHandler([.alert, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("UNUserNotification 알림이 클릭됨: \(response.notification.request.content.title)")
        // 알림 클릭 시 앱을 활성화
        NSApplication.shared.activate(ignoringOtherApps: true)
        completionHandler()
    }
}
