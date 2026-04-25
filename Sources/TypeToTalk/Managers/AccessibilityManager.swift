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
    private let promptKey = "AXTrustedCheckOptionPrompt" as CFString
    
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

    /// UI の「権限を再チェック」ボタン用。プロンプトを出さずに最新状態を取得して結果を返す。
    /// - Returns: 現在の `hasPermission` の最新値（true なら権限あり）
    @discardableResult
    func recheckPermissionAndOpenSettingsIfNeeded() -> Bool {
        refreshPermissionStatus()
        return hasPermission
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
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
