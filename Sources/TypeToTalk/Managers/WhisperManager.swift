import Foundation
import WhisperKit

enum WhisperLoadState: Equatable {
    case idle
    case loading
    case loaded(modelID: String)
    case failed(message: String)
}

@MainActor
class WhisperManager: ObservableObject {
    @Published var whisperKit: WhisperKit?
    @Published var isTranscribing = false
    @Published var lastTranscription: String = ""
    @Published var isLoadingModel = false
    @Published private(set) var loadState: WhisperLoadState = .idle
    @Published private(set) var loadingStatusText = "未読込"
    
    private let settings: SettingsManager
    private var loadedModelID: String?
    
    init(settings: SettingsManager) {
        self.settings = settings
    }
    
    var selectedModelID: String {
        settings.resolvedWhisperModelID ?? WhisperKit.recommendedModels().default
    }
    
    var loadedModelDisplayName: String {
        loadedModelID ?? "未読込"
    }
    
    var selectedModelDisplayName: String {
        selectedModelID
    }
    
    var needsExplicitLoad: Bool {
        whisperKit == nil || loadedModelID != selectedModelID
    }

    var canAutoLoad: Bool {
        !selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var statusText: String {
        switch loadState {
        case .idle:
            return needsExplicitLoad ? "未読込" : "準備完了"
        case .loading:
            return loadingStatusText
        case .loaded:
            return needsExplicitLoad ? "未読込" : "準備完了"
        case let .failed(message):
            return "失敗: \(message)"
        }
    }
    
    func loadSelectedModel() async {
        await setupWhisper(forceReload: true)
    }

    func ensureSelectedModelLoaded() async {
        guard canAutoLoad else { return }
        await setupWhisper(forceReload: false)
    }
    
    func unloadModel() {
        whisperKit = nil
        loadedModelID = nil
        loadState = .idle
    }
    
    private func setupWhisper(forceReload: Bool) async {
        let selectedModelID = self.selectedModelID
        if !forceReload, whisperKit != nil, loadedModelID == selectedModelID {
            return
        }
        
        isLoadingModel = true
        loadState = .loading
        loadingStatusText = "ダウンロード中..."
        defer { isLoadingModel = false }
        
        do {
            let modelPath = try await WhisperKit.download(variant: selectedModelID)
            loadingStatusText = "モデル読込中..."
            let kit = try await WhisperKit(model: selectedModelID, modelFolder: modelPath.path)
            self.whisperKit = kit
            self.loadedModelID = selectedModelID
            self.loadState = .loaded(modelID: selectedModelID)
            self.loadingStatusText = "準備完了"
            print("WhisperKit ready with model: \(selectedModelID)")
        } catch {
            self.whisperKit = nil
            self.loadedModelID = nil
            self.loadState = .failed(message: error.localizedDescription)
            self.loadingStatusText = "失敗: \(error.localizedDescription)"
            print("WhisperKit setup failed: \(error)")
        }
    }
    
    func transcribe(audioURL: URL) async -> String {
        guard let whisperKit = whisperKit else {
            return ""
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        do {
            // WhisperKit 0.18.0 の仕様に合わせる
            let results = try await whisperKit.transcribe(audioPath: audioURL.path)
            let combinedText = results.compactMap { $0.text }.joined(separator: " ")
            lastTranscription = combinedText
            return combinedText
        } catch {
            print("Transcription failed: \(error)")
            return ""
        }
    }
}
