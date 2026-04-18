import Foundation

@MainActor
class SettingsManager: ObservableObject {
    @Published var groqApiKey: String {
        didSet { UserDefaults.standard.set(groqApiKey, forKey: "groqApiKey") }
    }
    
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }
    
    @Published var dictionary: [DictionaryEntry] {
        didSet {
            if let encoded = try? JSONEncoder().encode(dictionary) {
                UserDefaults.standard.set(encoded, forKey: "userDictionary")
            }
        }
    }
    
    init() {
        self.groqApiKey = UserDefaults.standard.string(forKey: "groqApiKey") ?? ""
        self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? "以下の文字起こしテキストを、自然な日本語に修正してください。不要なフィラーは削除し、文脈を整えてください。"
        
        if let data = UserDefaults.standard.data(forKey: "userDictionary"),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            self.dictionary = decoded
        } else {
            // 初期サンプル
            self.dictionary = [
                DictionaryEntry(word: "TTT", reading: "ティーティーティー"),
                DictionaryEntry(word: "tamekuniz", reading: "ためくにず")
            ]
        }
    }
    
    func addEntry(word: String, reading: String) {
        dictionary.append(DictionaryEntry(word: word, reading: reading))
    }
    
    func removeEntry(at offsets: IndexSet) {
        dictionary.remove(atOffsets: offsets)
    }
}
