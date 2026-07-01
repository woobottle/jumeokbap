# Settings Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 주먹밥의 사용자 설정값과 플로팅 창 위치를 UserDefaults에 영속화하고, 미사용 코드 3건을 제거한다.

**Architecture:** `TimerManager`의 영속 프로퍼티 `didSet`에서 UserDefaults에 저장하고 `init(defaults:)`에서 복원한다. 창 위치는 `TimerManager`가 데이터를, `AppDelegate`가 실제 `NSWindow` 조작을 담당한다. 테스트는 주입된 별도 suite `UserDefaults`로 격리한다.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults, Swift Testing (`@Test`/`#expect`)

## Global Constraints

- macOS 14.0+ 타겟, `#if os(macOS)` 가드 기존 패턴 유지
- 저장 키 prefix: `jb.` (예: `jb.selectedMinutes`)
- `remaining` / `isRunning`은 영속화하지 않음
- 창 위치는 X/Y 둘 다 저장돼 있을 때만 복원
- 기존 코드 스타일(한글 주석, `@Published` + `didSet` 콜백 패턴) 따름

---

### Task 1: TimerManager 영속화 (프로퍼티 + init 주입)

**Files:**
- Modify: `Jumeokbap/TimerManager.swift`
- Test: `JumeokbapTest/JumeokbappTests.swift`

**Interfaces:**
- Produces:
  - `init(defaults: UserDefaults = .standard)` — 주입된 store에서 값 복원 및 이후 저장에 사용
  - `var selectedMinutes: Int` / `var alarmVolume: Double` / `var autoMute: Bool` / `var showFloatingDisplay: Bool` — 변경 시 자동 저장
  - `var savedFloatingOrigin: CGPoint?` — 저장된 창 위치(없으면 nil)
  - `func saveFloatingOrigin(_ point: CGPoint)` — 창 위치 저장

- [ ] **Step 1: Write the failing tests**

`JumeokbapTest/JumeokbappTests.swift` 상단 `import` 아래, `struct JumeokbappTests {` 내부에 추가:

```swift
    // 격리된 UserDefaults suite를 만들어 주입하는 헬퍼
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "jb.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    @Test func settingsPersistAcrossInstances() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TimerManager(defaults: defaults)
        first.selectedMinutes = 25
        first.alarmVolume = 0.9
        first.autoMute = true
        first.showFloatingDisplay = false

        let second = TimerManager(defaults: defaults)
        #expect(second.selectedMinutes == 25)
        #expect(second.alarmVolume == 0.9)
        #expect(second.autoMute == true)
        #expect(second.showFloatingDisplay == false)
    }

    @Test func defaultsWhenNothingStored() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = TimerManager(defaults: defaults)
        #expect(manager.selectedMinutes == 5)
        #expect(manager.alarmVolume == 0.5)
        #expect(manager.autoMute == false)
        #expect(manager.showFloatingDisplay == true)
    }

    @Test func floatingOriginRoundTrips() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TimerManager(defaults: defaults)
        #expect(first.savedFloatingOrigin == nil)
        first.saveFloatingOrigin(CGPoint(x: 100, y: 200))

        let second = TimerManager(defaults: defaults)
        #expect(second.savedFloatingOrigin == CGPoint(x: 100, y: 200))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Jumeokbap.xcodeproj -scheme jumeokb -destination 'platform=macOS' -only-testing:JumeokbappTests 2>&1 | tail -20`
Expected: FAIL — `TimerManager`에 `init(defaults:)` / `savedFloatingOrigin` / `saveFloatingOrigin` 없음 (컴파일 에러)

- [ ] **Step 3: Implement persistence in TimerManager**

`Jumeokbap/TimerManager.swift`를 아래로 수정한다.

먼저 파일 상단 `final class TimerManager: ObservableObject {` 바로 아래에 키 상수와 store 프로퍼티 추가:

```swift
    private enum Keys {
        static let selectedMinutes = "jb.selectedMinutes"
        static let alarmVolume = "jb.alarmVolume"
        static let autoMute = "jb.autoMute"
        static let showFloatingDisplay = "jb.showFloatingDisplay"
        static let floatingOriginX = "jb.floatingOriginX"
        static let floatingOriginY = "jb.floatingOriginY"
    }

    private let defaults: UserDefaults
```

`@Published` 프로퍼티들을 아래처럼 `didSet` 저장이 붙은 형태로 교체 (기존 `compactMode` 줄은 삭제):

```swift
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
```

`init(defaults:)` 추가 (프로퍼티 선언들 뒤, `formattedTime` 앞 등 클래스 본문 내):

```swift
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
```

창 위치 API 추가 (클래스 본문 내, 예: `sendNotification()` 앞):

```swift
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
```

주의: `init` 내 프로퍼티 대입에서는 `didSet`이 발동하지 않으므로 재저장이 일어나지 않는다(저장값은 이미 defaults에 있음). `register(defaults:)` 덕분에 미저장 시에도 기본값이 읽힌다.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Jumeokbap.xcodeproj -scheme jumeokb -destination 'platform=macOS' -only-testing:JumeokbappTests 2>&1 | tail -20`
Expected: PASS (신규 3개 + 기존 3개 통과)

- [ ] **Step 5: Commit**

```bash
git add Jumeokbap/TimerManager.swift JumeokbapTest/JumeokbappTests.swift
git commit -m "feat: persist TimerManager settings via UserDefaults

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: AppDelegate 창 위치 복원/저장 + 클램프 헬퍼

**Files:**
- Modify: `Jumeokbap/AppDelegate.swift`

**Interfaces:**
- Consumes: `timerManager.savedFloatingOrigin`, `timerManager.saveFloatingOrigin(_:)` (Task 1)
- Produces: `func clampToVisibleFrame(_ origin: CGPoint, size: NSSize, in visible: NSRect) -> CGPoint` (내부 헬퍼)

- [ ] **Step 1: Add clamp helper**

`Jumeokbap/AppDelegate.swift`의 `finishDrag()` 메서드 위(예: `finishDrag` 선언 앞)에 헬퍼 추가:

```swift
    // 창 원점을 화면 작업 영역 안으로 클램프
    func clampToVisibleFrame(_ origin: CGPoint, size: NSSize, in visible: NSRect) -> CGPoint {
        let minX = visible.minX
        let maxX = visible.maxX - size.width
        let minY = visible.minY
        let maxY = visible.maxY - size.height
        return CGPoint(x: max(minX, min(maxX, origin.x)),
                       y: max(minY, min(maxY, origin.y)))
    }
```

- [ ] **Step 2: Use saved origin in setupFloatingTimer**

`setupFloatingTimer()`에서 `initialRect` 계산부를 수정한다. 기존:

```swift
        let originX = visible.maxX - windowSize.width - margin
        let originY = visible.maxY - windowSize.height - margin
        let initialRect = NSRect(x: originX, y: originY, width: windowSize.width, height: windowSize.height)
```

를 아래로 교체:

```swift
        let defaultOrigin = CGPoint(x: visible.maxX - windowSize.width - margin,
                                    y: visible.maxY - windowSize.height - margin)
        let restored = timerManager.savedFloatingOrigin
            .map { clampToVisibleFrame($0, size: windowSize, in: visible) }
        let origin = restored ?? defaultOrigin
        let initialRect = NSRect(x: origin.x, y: origin.y, width: windowSize.width, height: windowSize.height)
```

- [ ] **Step 3: Save origin in finishDrag**

`finishDrag()`에서 클램프 블록을 헬퍼 호출로 바꾸고, `window.setFrame(...animate: true)` 직후에 저장을 추가한다.

기존 클램프 블록:

```swift
        // 클램프: 창이 화면 밖으로 나가지 않도록 제한
        let minX = visible.minX
        let maxX = visible.maxX - frame.size.width
        let minY = visible.minY
        let maxY = visible.maxY - frame.size.height
        frame.origin.x = max(minX, min(maxX, frame.origin.x))
        frame.origin.y = max(minY, min(maxY, frame.origin.y))
```

를 아래로 교체 (이후 스냅 로직이 `minX`/`maxX`를 참조하므로 그 두 값은 남긴다):

```swift
        // 클램프: 창이 화면 밖으로 나가지 않도록 제한
        let minX = visible.minX
        let maxX = visible.maxX - frame.size.width
        frame.origin = clampToVisibleFrame(frame.origin, size: frame.size, in: visible)
```

그리고 메서드 마지막 부분:

```swift
        window.setFrame(frame, display: true, animate: true)
        // 드래그 종료 후 기준점 업데이트
        initialWindowOrigin = frame.origin
        dragOffsetFromMouse = nil
```

를 아래로 교체 (저장 한 줄 추가):

```swift
        window.setFrame(frame, display: true, animate: true)
        // 드래그 종료 후 기준점 업데이트 및 위치 영속화
        initialWindowOrigin = frame.origin
        dragOffsetFromMouse = nil
        timerManager.saveFloatingOrigin(frame.origin)
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -project Jumeokbap.xcodeproj -scheme jumeokb -destination 'platform=macOS' 2>&1 | tail -15`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Jumeokbap/AppDelegate.swift
git commit -m "feat: restore and persist floating window position

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 미사용 코드 제거

**Files:**
- Modify: `Jumeokbap/JumeokbapApp.swift`
- Modify: `Jumeokbap/AppDelegate.swift`

**Interfaces:**
- Consumes: 없음 (순수 삭제). `compactMode`는 Task 1에서 이미 제거됨.

- [ ] **Step 1: Remove unused imports**

`Jumeokbap/JumeokbapApp.swift`의 `import SwiftData` (9번째 줄) 삭제.
`Jumeokbap/AppDelegate.swift`의 `import SwiftData` (3번째 줄) 삭제.

- [ ] **Step 2: Remove moveFloatingWindow(by:)**

`Jumeokbap/AppDelegate.swift`에서 아래 메서드 전체 삭제:

```swift
    func moveFloatingWindow(by translation: CGSize) {
        // 기존 상대 이동 방식(호환용) — 절대 마우스 추적을 우선 사용
        guard let window = floatingWindow, let initialOrigin = initialWindowOrigin else { return }
        var frame = window.frame
        frame.origin.x = initialOrigin.x + translation.width
        frame.origin.y = initialOrigin.y - translation.height
        window.setFrame(frame, display: false)
    }
```

(주의: `saveInitialWindowPosition()`는 별개 메서드이므로 건드리지 않는다. `moveFloatingWindow`만 삭제.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project Jumeokbap.xcodeproj -scheme jumeokb -destination 'platform=macOS' 2>&1 | tail -15`
Expected: BUILD SUCCEEDED (미사용 심볼 참조 에러 없음)

- [ ] **Step 4: Run full test suite**

Run: `xcodebuild test -project Jumeokbap.xcodeproj -scheme jumeokb -destination 'platform=macOS' -only-testing:JumeokbappTests 2>&1 | tail -20`
Expected: PASS (전체 6개)

- [ ] **Step 5: Commit**

```bash
git add Jumeokbap/JumeokbapApp.swift Jumeokbap/AppDelegate.swift
git commit -m "chore: remove unused SwiftData imports and moveFloatingWindow

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes

- `scheme` 이름은 `jumeokb` (`.xcodeproj/xcshareddata/xcschemes/jumeokb.xcscheme` 기준). 빌드 실패 시 `xcodebuild -list -project Jumeokbap.xcodeproj`로 scheme/destination 확인.
- 테스트 대상 이름은 `JumeokbappTests` (struct명). `-only-testing:` 인자가 안 맞으면 `-only-testing` 없이 전체 test 실행.
