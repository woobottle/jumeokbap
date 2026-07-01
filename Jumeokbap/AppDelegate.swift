import SwiftUI
import Swift
import UserNotifications


// MARK: - AppDelegate (Jumeokbap)
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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
            button.action = #selector(toggleMenu)
            button.target = self
        }

        // 메뉴 설정
        setupMenu()

        // TimerManager의 remaining 변경을 관찰해서 메뉴 바 업데이트
        timerManager.onRemainingChanged = { [weak self] in
            self?.updateStatusBarTitle()
        }
    }

    // 메뉴 설정
    func setupMenu() {
        let menu = NSMenu()
        
        // Settings 메뉴 항목
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // 구분선
        menu.addItem(NSMenuItem.separator())
        
        // Quit 메뉴 항목
        let quitItem = NSMenuItem(title: "Quit Jumeokbap", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    @objc func toggleMenu() {
        // 메뉴는 자동으로 표시됨
    }

    @objc func openSettings() {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func updateStatusBarTitle() {
        guard timerManager.isRunning else {
            statusItem.button?.title = "주먹밥"
            return
        }
        if timerManager.pomodoroEnabled {
            let icon = timerManager.currentPhase == .focus ? "🍅" : "☕️"
            statusItem.button?.title = "\(icon) \(timerManager.formattedTime)"
        } else {
            statusItem.button?.title = timerManager.formattedTime
        }
    }

    // 팝오버 (설정창)
    func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 280)
        popover.contentViewController = NSHostingController(rootView: SettingsView(timerManager: timerManager))
    }

    // 항상 위 플로팅 타이머
    func setupFloatingTimer() {
        let view = FloatingTimerView(timerManager: timerManager)
        let hosting = NSHostingView(rootView: view)
        // 초기 위치를 화면 우측 상단으로 배치
        let windowSize = NSSize(width: 120, height: 60)
        let margin: CGFloat = 12
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let defaultOrigin = CGPoint(x: visible.maxX - windowSize.width - margin,
                                    y: visible.maxY - windowSize.height - margin)
        let restored = timerManager.savedFloatingOrigin
            .map { clampToVisibleFrame($0, size: windowSize, in: visible) }
        let origin = restored ?? defaultOrigin
        let initialRect = NSRect(x: origin.x, y: origin.y, width: windowSize.width, height: windowSize.height)

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

    // 창 원점을 화면 작업 영역 안으로 클램프
    func clampToVisibleFrame(_ origin: CGPoint, size: NSSize, in visible: NSRect) -> CGPoint {
        let minX = visible.minX
        let maxX = visible.maxX - size.width
        let minY = visible.minY
        let maxY = visible.maxY - size.height
        return CGPoint(x: max(minX, min(maxX, origin.x)),
                       y: max(minY, min(maxY, origin.y)))
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
        frame.origin = clampToVisibleFrame(frame.origin, size: frame.size, in: visible)

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
        // 드래그 종료 후 기준점 업데이트 및 위치 영속화
        initialWindowOrigin = frame.origin
        dragOffsetFromMouse = nil
        timerManager.saveFloatingOrigin(frame.origin)
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
    }

    func setupAppIcon() {
        // 앱 아이콘을 TimerManager에 설정 (알림에 표시하기 위해)
        timerManager.appIconImage = NSApp?.applicationIconImage
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
