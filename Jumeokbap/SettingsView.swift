import SwiftUI

// MARK: - SettingsView (Jumeokbap)
struct SettingsView: View {
    @ObservedObject var timerManager: TimerManager

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

            Text("alarm volume:").font(.headline)
            Slider(value: $timerManager.alarmVolume, in: 0...1)
            Toggle("automatically mute after 5 seconds", isOn: $timerManager.autoMute)

            Divider()



            Toggle("floating display", isOn: $timerManager.showFloatingDisplay)

            Divider()

            Text("system settings:").font(.headline)
            Button("알림 설정 열기") {
                openSystemSettings()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .frame(width: 280)
    }
}
