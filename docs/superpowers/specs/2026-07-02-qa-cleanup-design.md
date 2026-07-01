# Phase 3 설계 — 출시 전 QA 정리

작성일: 2026-07-02
대상: 주먹밥 (Jumeokbap) macOS 메뉴바 타이머

## 배경 / 문제

출시(1.0) 전 두 가지 품질 갭을 정리한다.

1. 설정 UI의 "alarm volume" 슬라이더와 "automatically mute after 5 seconds" 토글이
   실제로 아무 동작도 하지 않는다(값만 저장). 동작하지 않는 컨트롤은 사용자 혼란/감점 요소.
2. `sendNotification`이 최신 `UNUserNotificationCenter`와 deprecated된 `NSUserNotification`을
   둘 다 전송한다. 같은 알림 2회 시도 + macOS 11.0 deprecation 경고 다수.

아이콘 정리는 조사 결과 `AppIcon.appiconset`의 모든 png가 `Contents.json`에서 실제 참조 중이라
삭제할 미사용 파일이 없어 **이번 범위에서 제외**한다.

## 목표

1. `alarmVolume` / `autoMute`를 관련 UI·저장 프로퍼티까지 제거 (미니멀 유지, 시스템 기본 사운드 사용)
2. 알림을 `UNUserNotificationCenter` 단일 경로로 정리, deprecated `NSUserNotification` 코드 전부 제거
3. deprecation 경고 소멸, 알림 1회 전송

## 비목표

- 커스텀 사운드/볼륨 재생 기능 (제거하기로 결정)
- 아이콘 파일 정리 (삭제할 미사용 파일 없음)
- 원격 푸시 알림 (로컬 앱, 사용 안 함)

## 결정 (확정됨)

- 볼륨/자동뮤트: **제거** (UI + 프로퍼티 + 저장키). 이미 저장된 `jb.alarmVolume`/`jb.autoMute`
  값은 읽지 않으므로 방치(마이그레이션/삭제 안 함, YAGNI).
- 알림: `UNUserNotificationCenter` **단일화**. `NSUserNotificationCenterDelegate` 채택·메서드·
  델리게이트 설정 제거. `registerForRemoteNotifications()` 호출도 제거(불필요).

## 컴포넌트 변경

### TimerManager.swift

- `Keys`에서 `alarmVolume`, `autoMute` 상수 삭제.
- `@Published var alarmVolume`, `@Published var autoMute` 프로퍼티 삭제.
- `register(defaults:)`에서 두 키 항목 삭제, `init` 복원부에서 두 대입 삭제.
- `sendNotification(for:)`: deprecated `NSUserNotification` 생성 및
  `NSUserNotificationCenter.default.deliver(...)` 블록 전부 삭제. `#if os(macOS)`의
  `UNUserNotificationCenter` 경로만 남기고, `onNotificationSent?()` 콜백은 유지(테스트용).
  - 주의: `onNotificationSent?()`가 `#if os(macOS)` 블록에 삼켜지지 않도록 블록 밖에서 호출.

### AppDelegate.swift

- 클래스 선언에서 `NSUserNotificationCenterDelegate` 채택 제거.
- `NSUserNotificationCenterDelegate` 메서드 3개 삭제:
  `userNotificationCenter(_:didDeliver:)`, `userNotificationCenter(_:didActivate:)`,
  `userNotificationCenter(_:shouldPresent:) -> Bool`.
- `requestNotificationPermission()`에서 `NSUserNotificationCenter.default.delegate = self`
  줄과 `NSApplication.shared.registerForRemoteNotifications()` 호출(및 그것만 감싼
  `DispatchQueue.main.async` 블록) 삭제.
- `UNUserNotificationCenterDelegate` 채택과 `willPresent`/`didReceive` 메서드는 유지
  (포그라운드 배너 표시 동작 보존).

### SettingsView.swift

- "alarm volume:" `Text`, `Slider(value: $timerManager.alarmVolume ...)`,
  `Toggle("automatically mute after 5 seconds", isOn: $timerManager.autoMute)` 및
  그 블록에 딸린 `Divider` 삭제. 나머지 레이아웃(프리셋/뽀모도로/컨트롤/floating/시스템 설정) 유지.

## 테스트 (JumeokbapTest)

- `settingsPersistAcrossInstances`, `defaultsWhenNothingStored`에서 `alarmVolume`/`autoMute`
  관련 세팅·단언 제거(나머지 키는 유지).
- 기존 알림 테스트(`timerCompletionSendsNotification`, `notificationContentIsCorrect`,
  Phase 2 페이즈 알림 경로)는 `onNotificationSent` 콜백 기반이라 그대로 통과해야 함 — 회귀 확인.
- 전체 스위트가 deprecation 경고 없이 빌드되는지 확인.

## 영향 없음

타이머/뽀모도로 로직, 창 위치 영속화, 프리셋, 포그라운드 배너 표시(`willPresent`).
