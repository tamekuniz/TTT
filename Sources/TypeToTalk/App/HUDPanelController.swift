import AppKit
import SwiftUI

/// HUD パネル（NSPanel.nonactivatingPanel）のライフサイクルと表示位置を管理するコントローラ。
///
/// SwiftUI 側だけでは `NSPanel(styleMask: [.borderless, .nonactivatingPanel])` を素直に
/// 構成できないため、AppKit ブリッジとして NSWindowController サブクラスを使う
/// （investigation.md §6.2、Option 1）。
///
/// - パネルはフォーカスを奪わない（nonactivatingPanel + canBecomeKey = false）。
/// - 画面下中央（visibleFrame.minY + 40px）に表示する。
/// - Phase A は単純な orderFrontRegardless / orderOut で表示・非表示する（フェードは Phase B）。
@MainActor
final class HUDPanelController: NSWindowController {
    private weak var coordinator: TypeToTalkCoordinator?
    private var hasPositioned = false

    init(coordinator: TypeToTalkCoordinator) {
        self.coordinator = coordinator

        let contentRect = NSRect(x: 0, y: 0, width: 280, height: 200)
        let panel = HUDPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: HUDView(coordinator: coordinator))
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// HUD を表示する。初回のみ画面下中央 (Dock 上 40px) に配置し、以降は直前の位置を保持する。
    func show() {
        guard let panel = window as? NSPanel else { return }
        if !hasPositioned {
            positionAtBottomCenter(panel: panel)
            hasPositioned = true
        }
        // フォーカスを奪わずに前面化する（makeKeyAndOrderFront は使わない）
        panel.orderFrontRegardless()
    }

    /// HUD を非表示にする。
    func hide() {
        window?.orderOut(nil)
    }

    private func positionAtBottomCenter(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let hudWidth: CGFloat = 280
        let hudHeight: CGFloat = 200
        let x = frame.midX - hudWidth / 2
        let y = frame.minY + 40
        panel.setFrame(
            NSRect(x: x, y: y, width: hudWidth, height: hudHeight),
            display: true
        )
    }
}

/// nonactivatingPanel でも借用キー扱いされないように canBecomeKey を明示的に false にする。
/// borderless + nonactivatingPanel の組合せで AppKit がデフォルトでキーを取りに行く挙動を
/// 抑制し、HUD 表示中に他アプリのキー入力を奪わないようにする。
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
