# Phase 1 설계 — 설정 영속화 + 코드 정리

작성일: 2026-07-01
대상: 주먹밥 (Jumeokbap) macOS 메뉴바 타이머

## 배경 / 문제

`TimerManager`의 사용자 설정값이 `UserDefaults`에 저장되지 않아, 앱을 재시작하면
프리셋 시간·볼륨·자동뮤트·플로팅 표시 설정이 모두 초기값으로 되돌아간다. 플로팅 창
위치도 항상 화면 우측 상단으로 초기화된다. 출시(1.0) 전 반드시 해결해야 할 완성도 갭.

함께, 사용되지 않는 코드(`import SwiftData`, `moveFloatingWindow(by:)`, `compactMode`)를
정리해 이후 Phase 2(뽀모도로 사이클) 작업의 기반을 깨끗이 한다.

## 목표

1. 사용자가 만지는 설정값과 플로팅 창 위치를 영속화해 재시작 후에도 유지
2. 미사용 코드 3건 제거
3. 영속화 로직에 대한 단위 테스트 추가

## 비목표 (이번 Phase 아님)

- `alarmVolume` / `autoMute`의 **실제 소리 재생·음소거 동작** (Phase 3) — 값 영속화만 함
- 뽀모도로 사이클 (Phase 2)
- UI 레이아웃 변경, 알림 이중전송 정리 (Phase 3)

## 접근 방식

`@Published` 프로퍼티의 `didSet`에서 `UserDefaults`에 직접 저장하고, `init()`에서 복원한다.
현재 코드가 이미 `didSet` 콜백 패턴(`remaining`, `showFloatingDisplay`)을 쓰고 있어 가장
자연스럽게 맞고, 외부 의존성이 없다. 창 위치처럼 뷰 밖(AppDelegate)에서 다루는 값도
`TimerManager`를 단일 창구로 일관 처리한다.

(대안으로 검토했으나 채택하지 않음: Codable 통짜 저장 — 현재 규모에 과함 / `@AppStorage` —
뷰 전용이라 AppDelegate·창 위치와 구조 불일치.)

## 저장 스키마

`UserDefaults.standard`, 키 prefix `jb.`:

| 키 | 타입 | 프로퍼티 | 기본값 |
|----|------|---------|--------|
| `jb.selectedMinutes` | Int | `selectedMinutes` | 5 |
| `jb.alarmVolume` | Double | `alarmVolume` | 0.5 |
| `jb.autoMute` | Bool | `autoMute` | false |
| `jb.showFloatingDisplay` | Bool | `showFloatingDisplay` | true |
| `jb.floatingOriginX` | Double | 플로팅 창 X | (없으면 우측상단) |
| `jb.floatingOriginY` | Double | 플로팅 창 Y | (없으면 우측상단) |

- `remaining` / `isRunning`은 저장하지 않는다 — 실행 중 타이머 상태는 재시작 시 초기화가 자연스럽다.
- 창 위치는 X/Y가 **둘 다** 저장돼 있을 때만 복원하고, 하나라도 없으면 기존 우측상단 로직을 쓴다.

## 컴포넌트 변경

### TimerManager.swift

- 파일 내 저장 키 상수 모음 `private enum Keys` 추가.
- 기본값은 `UserDefaults`의 `register(defaults:)`로 등록해 "키 없음" 처리를 단순화.
- 영속 프로퍼티의 `didSet`에서 해당 값을 저장:
  - `selectedMinutes`, `alarmVolume`, `autoMute` — `didSet` 신규 추가
  - `showFloatingDisplay` — 기존 `didSet`(콜백 호출)에 저장 한 줄 추가
- `init(defaults: UserDefaults = .standard)` 추가:
  - 주입받은 `defaults`에서 각 값을 복원. 테스트에서 별도 suite `UserDefaults`를 주입할 수 있게 연다.
  - 복원 대상 `defaults`를 인스턴스에 보관해 이후 저장에도 같은 store를 사용한다.
- 창 위치 API:
  - `var savedFloatingOrigin: CGPoint?` (computed) — X/Y 둘 다 있으면 `CGPoint`, 아니면 `nil`
  - `func saveFloatingOrigin(_ point: CGPoint)` — X/Y 저장
- `compactMode` 프로퍼티 **제거**.

창 위치는 값(데이터)만 `TimerManager`가 보유하고, 실제 `NSWindow` 조작은 `AppDelegate`가 담당(역할 분리).

### AppDelegate.swift

- `setupFloatingTimer()`: 초기 위치를 `timerManager.savedFloatingOrigin`이 있으면 그 값으로,
  없으면 기존 우측상단 로직으로 결정. 복원 위치는 화면 밖으로 나가지 않도록 클램프한다.
  - `finishDrag()`의 클램프 로직을 헬퍼 `clampToVisibleFrame(_ origin:size:) -> CGPoint`로 추출해 재사용.
- `finishDrag()`: 스냅·클램프 후 최종 위치를 `timerManager.saveFloatingOrigin(frame.origin)`로 저장.
- `import SwiftData` 제거.
- `moveFloatingWindow(by:)` 메서드 제거.

### JumeokbapApp.swift

- `import SwiftData` 제거.

## 테스트 (JumeokbapTest)

- 영속화 왕복 테스트: 격리를 위해 임의 suite name의 `UserDefaults` 인스턴스를 만들어 주입.
  - 값 세팅 → 해당 `UserDefaults`에 저장됐는지 확인
  - 같은 `defaults`로 새 `TimerManager` 생성 시 값이 복원되는지 확인
  - 창 위치 저장 후 `savedFloatingOrigin`이 저장한 좌표를 반환하는지, 미저장 시 `nil`인지 확인
- 각 테스트 후 suite `removePersistentDomain(forName:)`으로 정리.

## 영향 없음

알림, UI 레이아웃, 뽀모도로(Phase 2). 기존 드래그·스냅 동작은 클램프 헬퍼 추출 외 로직 변화 없음.
