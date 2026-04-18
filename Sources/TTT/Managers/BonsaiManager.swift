import Foundation
import MLX

@MainActor
class BonsaiManager: ObservableObject {
    @Published var isModelLoaded = false
    
    private var modelURL: URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ttt/models/bonsai-8b-1bit")
    }
    
    init() {
        // init内でのTask利用を安全にする
        Task { [weak self] in
            await self?.checkModel()
        }
    }
    
    private func checkModel() async {
        guard let url = modelURL, FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        isModelLoaded = true
    }
    
    func processText(_ text: String, prompt: String = "文字起こしを修正して：") async -> String {
        guard isModelLoaded else { return text }
        return text
    }
}
