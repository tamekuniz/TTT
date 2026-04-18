import Foundation

struct DictionaryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var word: String      // 正しい表記 (例: TTT)
    var reading: String   // 聞き間違いやすい読み (例: てぃーてぃーてぃー)
}
