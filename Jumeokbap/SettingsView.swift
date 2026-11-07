import SwiftUI
import FirebaseAnalytics
import FirebaseCrashlytics

// MARK: - AnalyticsConsent (분석 데이터 수집 설정)
/// "분석 데이터 수집" 설정(기본 켜짐). 끄면 Firebase Analytics·Crashlytics 수집을 둘 다 끈다.
///
/// - 저장 형식은 UserDefaults 문자열 "1"(켬)/"0"(끔). 읽을 땐 "true"/"false"도 인정한다.
/// - 앱 시작 때는 저장값이 "0"(끔)일 때만 적용한다. "1"·값 없음이면 Firebase를 건드리지 않는다
///   — 끈 설정은 Firebase가 기기에 따로 저장해 두므로, true로 가정해 켜면 꺼 둔 수집이 다시 켜질 수 있다.
/// - Firebase의 Swift API는 동기·무실패라 롤백할 실패 경로가 없다. 끌 때는 Firebase를 먼저 끄고 저장,
///   켤 때는 저장한 뒤 켠다(중간에 앱이 죽어도 꺼진 쪽이 남게).
final class AnalyticsConsent {
    static let key = "analytics.collectionEnabled"
    static let shared = AnalyticsConsent()

    private let defaults: UserDefaults
    private let applyToSDK: (Bool) -> Void

    init(defaults: UserDefaults = .standard, apply: @escaping (Bool) -> Void = AnalyticsConsent.applyToFirebase) {
        self.defaults = defaults
        self.applyToSDK = apply
    }

    /// 명시적으로 저장된 값. 없거나 알 수 없는 값이면 nil.
    var storedValue: Bool? {
        switch defaults.string(forKey: Self.key) {
        case "1", "true": return true
        case "0", "false": return false
        default: return nil
        }
    }

    /// 화면 표시용 값(저장값이 없으면 기본 켜짐).
    var isEnabled: Bool { storedValue ?? true }

    /// 앱 시작 직후(FirebaseApp.configure() 다음) 한 번 호출. 저장값이 "0"(끔)일 때만 false를 적용한다.
    /// "1"이거나 값이 없으면 아무것도 호출하지 않는다 — 켬은 Firebase가 기기에 이미 저장해 두므로 다시 적용할
    /// 필요가 없고, 끄기 저장이 실패해 남은 예전 "1"이 수집을 다시 켜지 않게 하기 위해서다.
    func applyStoredValue() {
        guard storedValue == false else { return }
        applyToSDK(false)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            defaults.set("1", forKey: Self.key)
            applyToSDK(true)
        } else {
            applyToSDK(false)
            defaults.set("0", forKey: Self.key)
        }
    }

    static func applyToFirebase(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }
}

// MARK: - SettingsView (Jumeokbap)
struct SettingsView: View {
    @ObservedObject var timerManager: TimerManager
    @State private var analyticsEnabled = AnalyticsConsent.shared.isEnabled

    private func openSystemSettings() {
        #if os(macOS)
        // macOS에서 시스템 알림 설정 열기
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("timer presets (min):").font(.headline)
            HStack {
                ForEach([1, 2, 5, 10, 25], id: \.self) { minute in
                    Button("\(minute)") {
                        timerManager.selectedMinutes = minute
                    }
                    .buttonStyle(.bordered)
                    .tint(timerManager.selectedMinutes == minute ? .accentColor : .gray)
                }
            }

            Divider()

            Toggle("뽀모도로 모드", isOn: $timerManager.pomodoroEnabled)
                .font(.headline)

            if timerManager.pomodoroEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper("집중 \(timerManager.focusMinutes)분", value: $timerManager.focusMinutes, in: 1...90)
                    Stepper("짧은 휴식 \(timerManager.shortBreakMinutes)분", value: $timerManager.shortBreakMinutes, in: 1...30)
                    Stepper("긴 휴식 \(timerManager.longBreakMinutes)분", value: $timerManager.longBreakMinutes, in: 1...60)
                    Stepper("\(timerManager.cyclesUntilLongBreak)세션마다 긴 휴식", value: $timerManager.cyclesUntilLongBreak, in: 2...8)
                    HStack(spacing: 4) {
                        Text("진행:")
                        ForEach(0..<timerManager.cyclesUntilLongBreak, id: \.self) { index in
                            Text(index < timerManager.completedFocusSessions ? "●" : "○")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                }
                .padding(.leading, 4)
            }

            Divider()

            Text("timer controls:").font(.headline)
            HStack {
                Button("시작") {
                    timerManager.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(timerManager.isRunning)

                Button("정지") {
                    timerManager.stop()
                }
                .buttonStyle(.bordered)
                .disabled(!timerManager.isRunning)

                Button("리셋") {
                    timerManager.reset()
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Toggle("floating display", isOn: $timerManager.showFloatingDisplay)

            Divider()

            Text("system settings:").font(.headline)
            Button("알림 설정 열기") {
                openSystemSettings()
            }
            .buttonStyle(.bordered)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("분석 데이터 수집", isOn: $analyticsEnabled)
                    .font(.headline)
                    .onChange(of: analyticsEnabled) { _, enabled in
                        AnalyticsConsent.shared.setEnabled(enabled)
                    }
                Text("익명 이용 통계·충돌 기록을 보내 앱 개선에 써요. 끄면 이후 전송하지 않아요.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .frame(width: 280)
    }
}
