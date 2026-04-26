import SwiftUI

/// 録音中・処理中の状態を画面下中央に表示する HUD パネル用 View。
///
/// 旧 TypeToTalkMainView をベースに以下を変更:
/// - SettingsLink / alert 修飾子を削除（HUD は表示専用、設定はメニューバーから開く）
/// - マイクボタンサイズを 88 → 72 に縮小
/// - 全体サイズを 360x300 → 280x200 に縮小
///
/// HUD は `HUDPanelController` 経由で `NSPanel(nonactivatingPanel)` の contentView として表示される。
/// HUD 上のマイクボタンタップでも録音開始/停止できる（coordinator.toggleRecording()）。
struct HUDView: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    await coordinator.toggleRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(micButtonColor)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .scaleEffect(isPulsing ? 1.08 : 1.0)
                        .opacity(isPulsing ? 0.85 : 1.0)
                        .animation(
                            coordinator.recorder.isRecording
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .easeInOut(duration: 0.2),
                            value: isPulsing
                        )
                    if coordinator.isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.1)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isProcessing)
            .help("録音開始 / 停止")
            .onChange(of: coordinator.recorder.isRecording) { _, recording in
                isPulsing = recording
            }

            VStack(spacing: 6) {
                modelStatusRow(
                    title: "Whisper",
                    detail: coordinator.settings.whisperDisplayName,
                    status: coordinator.whisper.statusText
                )
                modelStatusRow(
                    title: "Formatter",
                    detail: coordinator.activeFormatterDisplayName,
                    status: coordinator.formatterStatusText
                )
            }
        }
        .padding(16)
        .frame(width: 280, height: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var micButtonColor: Color {
        if coordinator.recorder.isRecording {
            return Color(red: 0.05, green: 0.35, blue: 0.80)
        }
        if coordinator.whisper.whisperKit != nil {
            return Color(red: 0.10, green: 0.47, blue: 0.95)
        }
        return Color(red: 0.45, green: 0.83, blue: 0.98)
    }

    private func modelStatusRow(
        title: String,
        detail: String,
        status: String
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            statusBadge(status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
    }

    private func statusBadge(_ value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(for: value))
                .frame(width: 7, height: 7)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
        .allowsHitTesting(false)
        .accessibilityAddTraits(.isStaticText)
    }

    private func statusColor(for value: String) -> Color {
        if value.contains("準備完了") || value.contains("完了") {
            return Color(red: 0.18, green: 0.67, blue: 0.37)
        }
        if value.contains("読込中") || value.contains("録音中") {
            return Color(red: 0.95, green: 0.64, blue: 0.16)
        }
        if value.contains("失敗") || value.contains("未接続") || value.contains("未読込") {
            return Color(red: 0.77, green: 0.42, blue: 0.18)
        }
        return Color.secondary.opacity(0.7)
    }
}
