# Phase 2 설계 — 뽀모도로 사이클 (모드 분리)

작성일: 2026-07-01
대상: 주먹밥 (Jumeokbap) macOS 메뉴바 타이머
다이어그램: Excalidraw scene `25aREIiZXOx` (워크스페이스 7KseH7BeB1S)

## 배경 / 문제

현재 타이머는 프리셋(1/2/5/10/25분) 중 하나를 골라 단발 카운트다운만 한다.
집중→휴식을 반복하는 뽀모도로 사용 흐름을 지원하지 않는다. Phase 1(설정 영속화) 위에
사이클 기능을 얹어 제품 가치를 높인다.

## 목표

1. "뽀모도로 모드" 토글 추가 — OFF면 기존 단발 타이머, ON이면 집중/휴식 사이클
2. 집중→(짧은/긴)휴식→집중 자동 순환, 페이즈 종료 시 알림 + 다음 페이즈 자동 시작
3. 4세션마다 긴 휴식, 사이클 진행 상태를 UI에 표시
4. 사이클 파라미터(집중/짧은휴식/긴휴식 분, N세션) 설정에서 조절 + 영속화

## 비목표 (이번 Phase 아님)

- 하루 누적 세션 통계 / 날짜별 기록 (후속 통계 기능)
- `alarmVolume`/`autoMute` 실제 소리 동작 (Phase 3)
- 알림 이중전송 정리, 아이콘 정리 (Phase 3)

## 설계 결정 (확정됨)

- **모드 분리**: 사이클은 토글로 켜는 별도 모드. 기존 단발 동작 완전 보존.
- **파라미터**: 기본값 집중 25 / 짧은 휴식 5 / 긴 휴식 15분, 4세션마다 긴 휴식. 설정에서 숫자 조절 가능.
- **자동 시작**: 페이즈 종료 시 알림 후 다음 페이즈 타이머를 즉시 시작. 사용자가 정지를 누를 때까지 무한 순환.
- **세션 카운트**: 현재 사이클 진행분만(0…N), 긴 휴식 후 0으로 리셋. 영속화하지 않음(런타임 상태).
- **표시**: 메뉴바 아이콘+시간, 플로팅 창 페이즈별 색조, 설정 팝오버 진행 점(n/N).

## 컴포넌트 변경

### TimerManager.swift — 상태 모델

새 영속 프로퍼티 (Phase 1 `didSet` 저장 패턴 재사용, `register(defaults:)`로 기본값):

| 프로퍼티 | 타입 | 기본 | 저장키 |
|---|---|---|---|
| `pomodoroEnabled` | Bool | false | `jb.pomodoroEnabled` |
| `focusMinutes` | Int | 25 | `jb.focusMinutes` |
| `shortBreakMinutes` | Int | 5 | `jb.shortBreakMinutes` |
| `longBreakMinutes` | Int | 15 | `jb.longBreakMinutes` |
| `cyclesUntilLongBreak` | Int | 4 | `jb.cyclesUntilLongBreak` |

새 런타임 상태 (비영속, `@Published`):

- `enum Phase { case focus, shortBreak, longBreak }`
- `currentPhase: Phase = .focus`
- `completedFocusSessions: Int = 0` — 현재 사이클 내 완료한 집중 수(0…`cyclesUntilLongBreak`)

`pomodoroEnabled == false`면 `currentPhase`/`completedFocusSessions`는 무시되고 기존
`selectedMinutes` 단발 동작을 유지한다.

헬퍼:
- `func phaseMinutes(_ phase: Phase) -> Int` — 페이즈별 분 반환(focus→focusMinutes 등)

### TimerManager.swift — 전환 로직

**전환 순수 함수** (테스트 용이하게 분리):

```
func nextPhase(from phase: Phase, sessions: Int) -> (phase: Phase, sessions: Int)
```

규칙:
- `.focus` 입력 → sessions+1 계산; `sessions+1 >= cyclesUntilLongBreak`면 `(.longBreak, sessions+1)`, 아니면 `(.shortBreak, sessions+1)`
- `.shortBreak` 입력 → `(.focus, sessions)` (변화 없음)
- `.longBreak` 입력 → `(.focus, 0)` (리셋)

**start()**:
- `pomodoroEnabled`면 `currentPhase = .focus`, `completedFocusSessions = 0`, `remaining = phaseMinutes(.focus) * 60`
- 아니면 기존 단발: `remaining = selectedMinutes * 60`
- 이후 기존 `Timer.scheduledTimer` 흐름 재사용

**Timer 콜백 (`remaining == 0` 도달)**:
- 단발 모드: 기존대로 `stop()` + `sendNotification()`
- 뽀모도로 모드:
  1. `sendNotification(for: currentPhase)` 전송
  2. `(next, sessions) = nextPhase(from: currentPhase, sessions: completedFocusSessions)`
  3. `currentPhase = next`, `completedFocusSessions = sessions`
  4. `remaining = phaseMinutes(next) * 60` — 타이머는 계속 실행(정지하지 않음)

**stop() / reset()**: 기존 동작 유지 + 사이클 중단. `reset()`은 `currentPhase = .focus`, `completedFocusSessions = 0`.

### TimerManager.swift — 알림

`sendNotification(for phase: Phase? = nil)`:
- 뽀모도로: `.focus` 종료 → "집중 완료! 휴식하세요", 휴식(`.shortBreak`/`.longBreak`) 종료 → "휴식 끝! 다시 집중"
- 단발(phase == nil): 기존 "⏰ N분 완료!" 문구 유지
- 기존 UN + NS 이중 전송 구조는 이번 Phase에서 건드리지 않는다(Phase 3).

### AppDelegate.swift — 메뉴바

`updateStatusBarTitle()`:
- 단발 모드 또는 미실행: 기존과 동일 (`formattedTime` / "주먹밥")
- 뽀모도로 실행 중: 페이즈 아이콘 + 시간 → 집중 `🍅 MM:SS`, 휴식 `☕️ MM:SS`

### FloatingTimerView.swift — 색조

`currentPhase`에 따라 배경 색조 변경:
- 집중 / 단발: 기존 어두운색(`Color.black.opacity`) 유지
- 휴식(short/long): 살짝 다른 톤(짙은 청록 계열)

### SettingsView.swift — 설정 UI

- 상단에 `Toggle("뽀모도로 모드", isOn: $timerManager.pomodoroEnabled)` 추가
- `pomodoroEnabled`일 때만 노출: 집중/짧은휴식/긴휴식 분, "N세션마다 긴 휴식" (Stepper)
- 진행 점: `completedFocusSessions` / `cyclesUntilLongBreak`을 `●`/`○`로 표시
- 기존 프리셋·시작/정지/리셋 유지. 뽀모도로 ON이면 시작 시 사이클 값 사용.

## 데이터 흐름

토글/파라미터 변경 → `TimerManager` `@Published` didSet → UserDefaults 저장 + UI 갱신.
`start()` → Timer 1초 틱 → `remaining==0` → (뽀모도로면) 알림+전환+자동 재시작 → 메뉴바/플로팅
`onRemainingChanged`·`currentPhase` 관찰로 갱신.

## 테스트 (JumeokbapTest)

- `nextPhase(from:sessions:)` 순수 함수 단위 테스트:
  - focus(sessions 0..2) → shortBreak, sessions+1
  - focus(sessions == cyclesUntilLongBreak-1) → longBreak, sessions+1
  - shortBreak → focus, sessions 불변
  - longBreak → focus, 0
- `phaseMinutes` 반환값 테스트
- 사이클 설정 영속화 왕복 테스트(Phase 1 주입 패턴 재사용): pomodoroEnabled/focusMinutes 등 저장→새 인스턴스 복원
- 단발 모드 회귀: `pomodoroEnabled == false`일 때 기존 start/stop 동작 불변

## 영향 없음

Phase 1 영속화(창 위치 등), 드래그/스냅, 기존 단발 타이머 경로.
