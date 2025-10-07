import SwiftUI

// MARK: - FloatingTimerView (Jumeokbap)
struct FloatingTimerView: View {
    @ObservedObject var timerManager: TimerManager
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragStartLocation: CGPoint?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(isHovering ? 0.7 : 0.75))
            Text(timerManager.formattedTime)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding()

            // Hover 시 닫기 버튼
            if isHovering {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            timerManager.showFloatingDisplay = false
                        }) {
                            Text("×")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 8)
                        .padding(.top, 6)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 120, height: 60)
        .shadow(radius: isHovering ? 8 : 5)
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 0.1)
                .onChanged { value in
                    if !isDragging {
                        timerManager.onDragStart?()
                        isDragging = true
                    }
                    timerManager.onDragWindow?(value.translation)
                }
                .onEnded { value in
                    isDragging = false
                    timerManager.onDragEnd?(value.translation)
                }
        )
    }
}
