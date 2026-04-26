import Foundation
import AppKit

@MainActor
class AccessibilityManager: ObservableObject {
    enum InsertResult {
        case success
        case missingPermission
        case noFocusedElement
        case unsupportedTarget
    }

    @Published var hasPermission = false
    /// アクセシビリティ権限 polling 中かどうか（重複起動防止 + UI 観測用）。
    /// @Published で公開して View 側で進行表示できるようにする。
    @Published private(set) var isPolling: Bool = false
    private let promptKey = "AXTrustedCheckOptionPrompt" as CFString

    /// 権限取得待ち polling 用の Task。stop / 再起動時に cancel する。
    private var pollingTask: Task<Void, Never>?

    init() {
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        hasPermission = AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = [promptKey: true] as CFDictionary
        hasPermission = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// AXIsProcessTrusted() を 1 秒間隔で polling し、true を検出した瞬間 onGranted を呼ぶ。
    ///
    /// - Parameters:
    ///   - onGranted: 権限が付与された瞬間に MainActor 上で 1 度だけ呼ばれる。
    ///                呼び出し側はここで restartApp() などの後処理を行う。
    ///   - timeoutSeconds: タイムアウト秒数。default 300 秒（5 分）。
    ///                     経過したら polling を停止し onGranted は呼ばない。
    ///
    /// 既に isPolling == true のときは早期 return（重複起動防止）。
    /// AXIsProcessTrusted() はプロセス内キャッシュされる可能性があるが、
    /// 経験上 polling で true を返すケースもあるため、検出時は呼び出し側で restartApp する想定。
    func startPermissionPolling(
        onGranted: @escaping @MainActor () -> Void,
        timeoutSeconds: Int = 300
    ) {
        if isPolling {
            return
        }
        // 念のため既存タスクをキャンセル
        pollingTask?.cancel()

        isPolling = true
        let start = Date()

        pollingTask = Task { @MainActor [weak self] in
            defer {
                // 終了時（成功/タイムアウト/キャンセル）どの経路でも isPolling を必ず false に戻す
                self?.isPolling = false
                self?.pollingTask = nil
            }

            while !Task.isCancelled {
                // 1 秒待機
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }

                // 権限チェック
                if AXIsProcessTrusted() {
                    self?.hasPermission = true
                    onGranted()
                    return
                }

                // タイムアウト判定
                if Date().timeIntervalSince(start) >= Double(timeoutSeconds) {
                    return
                }
            }
        }
    }

    /// 進行中の権限 polling を停止する。
    /// - 呼んだ時点で onGranted は呼ばれない（権限付与直前でも一切発火しない保証はないが、cancel 後の sleep 復帰時に Task.isCancelled で抜ける）。
    func stopPermissionPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    func insertText(_ text: String) -> InsertResult {
        guard !text.isEmpty else { return .success }
        // キャッシュ短路評価による「権限後付け非反映」を避けるため、毎回最新状態を取り直す
        refreshPermissionStatus()
        guard hasPermission else {
            return .missingPermission
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else {
            return .noFocusedElement
        }

        if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success {
            return .success
        }

        if typeTextUsingEvents(text) {
            return .success
        }

        return .unsupportedTarget
    }

    private func typeTextUsingEvents(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        for scalar in text.unicodeScalars {
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                return false
            }

            var value = UInt16(scalar.value)
            withUnsafePointer(to: &value) { pointer in
                keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: pointer)
                keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: pointer)
            }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }

        return true
    }
}
