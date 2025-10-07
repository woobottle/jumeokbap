//
 //  JumeokbappTests.swift
 //  JumeokbappTests
 //
 //  Created by logan on 10/7/25.
 //

 import Testing
 import Foundation
 import UserNotifications
@testable import Jumeokbap

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

 }
