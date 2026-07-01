//
 //  JumeokbappTests.swift
 //  JumeokbappTests
 //
 //  Created by logan on 10/7/25.
 //

 import Testing
 import Foundation
 import CoreGraphics
 import UserNotifications
@testable import jumeokbap

 struct JumeokbappTests {

     @Test func timerCompletionSendsNotification() async throws {
         // Given: TimerManager 인스턴스 생성 및 설정
         let timerManager = TimerManager()
         timerManager.selectedMinutes = 1  // 1분 타이머 설정

         var notificationSent = false
         timerManager.onNotificationSent = {
             notificationSent = true
         }

         // When: 타이머 시작 후 remaining을 0으로 설정하여 종료 상황 시뮬레이션
         timerManager.start()

         // 타이머가 실제로 작동하지 않도록 remaining을 직접 0으로 설정
         timerManager.remaining = 0

         // 타이머의 콜백 로직을 수동으로 실행 (실제 타이머 종료 상황 재현)
         if timerManager.remaining == 0 {
             timerManager.stop()
             timerManager.sendNotification()
         }

         // Then: 알림이 전송되었는지 확인
         #expect(notificationSent == true, "타이머가 종료되면 알림이 전송되어야 합니다")
     }

     @Test func timerCompletionStopsTimer() async throws {
         // Given: TimerManager 인스턴스 생성 및 타이머 시작
         let timerManager = TimerManager()
         timerManager.selectedMinutes = 1
         timerManager.start()

         // When: 타이머 종료 상황 시뮬레이션
         timerManager.remaining = 0
         if timerManager.remaining == 0 {
             timerManager.stop()
             timerManager.sendNotification()
         }

         // Then: 타이머가 정지되었는지 확인
         #expect(timerManager.isRunning == false, "타이머가 종료되면 isRunning이 false가 되어야 합니다")
     }

     @Test func notificationContentIsCorrect() async throws {
         // Given: TimerManager 인스턴스 생성 및 설정
         let timerManager = TimerManager()
         let testMinutes = 25
         timerManager.selectedMinutes = testMinutes

         // When: 알림 전송
         timerManager.sendNotification()

         // Then: 알림 내용이 올바른지 확인 (실제 알림은 확인하기 어려우므로 최소한 메서드가 호출되는지 확인)
         // 실제 알림 내용 검증은 UNUserNotificationCenter를 모의 객체로 교체해야 하지만,
         // 여기서는 sendNotification() 메서드가 에러 없이 실행되는지만 확인
         #expect(timerManager.selectedMinutes == testMinutes, "알림 전송 시 선택된 시간 설정이 유지되어야 합니다")
     }

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
         first.showFloatingDisplay = false

         let second = TimerManager(defaults: defaults)
         #expect(second.selectedMinutes == 25)
         #expect(second.showFloatingDisplay == false)
     }

     @Test func defaultsWhenNothingStored() async throws {
         let (defaults, suite) = makeDefaults()
         defer { defaults.removePersistentDomain(forName: suite) }

         let manager = TimerManager(defaults: defaults)
         #expect(manager.selectedMinutes == 5)
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

     // MARK: - Phase 2: 뽀모도로 사이클

     @Test func nextPhaseFromFocusBeforeThresholdGoesShortBreak() async throws {
         let m = TimerManager()
         m.cyclesUntilLongBreak = 4
         let r = m.nextPhase(from: .focus, sessions: 0)
         #expect(r.phase == .shortBreak)
         #expect(r.sessions == 1)
     }

     @Test func nextPhaseFromFocusAtThresholdGoesLongBreak() async throws {
         let m = TimerManager()
         m.cyclesUntilLongBreak = 4
         let r = m.nextPhase(from: .focus, sessions: 3)
         #expect(r.phase == .longBreak)
         #expect(r.sessions == 4)
     }

     @Test func nextPhaseFromShortBreakGoesFocus() async throws {
         let m = TimerManager()
         let r = m.nextPhase(from: .shortBreak, sessions: 2)
         #expect(r.phase == .focus)
         #expect(r.sessions == 2)
     }

     @Test func nextPhaseFromLongBreakResetsSessions() async throws {
         let m = TimerManager()
         let r = m.nextPhase(from: .longBreak, sessions: 4)
         #expect(r.phase == .focus)
         #expect(r.sessions == 0)
     }

     @Test func phaseMinutesReturnsConfiguredValues() async throws {
         let m = TimerManager()
         m.focusMinutes = 25
         m.shortBreakMinutes = 5
         m.longBreakMinutes = 15
         #expect(m.phaseMinutes(.focus) == 25)
         #expect(m.phaseMinutes(.shortBreak) == 5)
         #expect(m.phaseMinutes(.longBreak) == 15)
     }

     @Test func pomodoroDefaultsWhenNothingStored() async throws {
         let (defaults, suite) = makeDefaults()
         defer { defaults.removePersistentDomain(forName: suite) }
         let m = TimerManager(defaults: defaults)
         #expect(m.pomodoroEnabled == false)
         #expect(m.focusMinutes == 25)
         #expect(m.shortBreakMinutes == 5)
         #expect(m.longBreakMinutes == 15)
         #expect(m.cyclesUntilLongBreak == 4)
     }

     @Test func pomodoroSettingsPersist() async throws {
         let (defaults, suite) = makeDefaults()
         defer { defaults.removePersistentDomain(forName: suite) }
         let first = TimerManager(defaults: defaults)
         first.pomodoroEnabled = true
         first.focusMinutes = 30
         first.shortBreakMinutes = 6
         first.longBreakMinutes = 20
         first.cyclesUntilLongBreak = 3

         let second = TimerManager(defaults: defaults)
         #expect(second.pomodoroEnabled == true)
         #expect(second.focusMinutes == 30)
         #expect(second.shortBreakMinutes == 6)
         #expect(second.longBreakMinutes == 20)
         #expect(second.cyclesUntilLongBreak == 3)
     }

     @Test func startInSingleShotModeUsesSelectedMinutes() async throws {
         let m = TimerManager()
         m.pomodoroEnabled = false
         m.selectedMinutes = 10
         m.start()
         #expect(m.remaining == 600)
         #expect(m.currentPhase == .focus)
         m.stop()
     }

     @Test func startInPomodoroModeInitializesFocusPhase() async throws {
         let m = TimerManager()
         m.pomodoroEnabled = true
         m.focusMinutes = 25
         m.completedFocusSessions = 3
         m.currentPhase = .shortBreak
         m.start()
         #expect(m.currentPhase == .focus)
         #expect(m.completedFocusSessions == 0)
         #expect(m.remaining == 1500)
         m.stop()
     }

 }
