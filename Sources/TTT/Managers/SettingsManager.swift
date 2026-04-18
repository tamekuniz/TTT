import Foundation

@MainActor
class SettingsManager: ObservableObject {
    @Published var groqApiKey: String {
        didSet { UserDefaults.standard.set(groqApiKey, forKey: "groqApiKey") }
    }
    
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }
    
    init() {
        self.groqApiKey = UserDefaults.standard.string(forKey: "groqApiKey") ?? ""
        self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? "以下の文字起こしテキストを、自然な日本語に修正してください。不要なフィラーは削除し、文脈を整えてください。"
    }
}
