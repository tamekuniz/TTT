import Foundation
import AppKit

@MainActor
class AccessibilityManager: ObservableObject {
    @Published var hasPermission = false
    
    init() {
        // 初期化時に非同期を使わず、メインスレッドで直接チェック
        checkPermission()
    }
    
    func checkPermission() {
        // システムの定数をそのまま使うと Swift 6 で警告が出るため、文字列リテラルで代用する手法も一般的です
        // kAXTrustedCheckOptionPrompt の実体は "AXTrustedCheckOptionPrompt" です
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        hasPermission = AXIsProcessTrustedWithOptions(options)
    }
    
    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement as! AXUIElement? {
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        }
    }
}
