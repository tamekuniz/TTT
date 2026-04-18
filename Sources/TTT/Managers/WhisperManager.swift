import Foundation
import WhisperKit

@MainActor
class WhisperManager: ObservableObject {
    @Published var whisperKit: WhisperKit?
    @Published var isTranscribing = false
    @Published var lastTranscription: String = ""
    
    init() {
        Task { [weak self] in
            await self?.setupWhisper()
        }
    }
    
    private func setupWhisper() async {
        do {
            let model = "openai/whisper-base"
            let modelPath = try await WhisperKit.download(variant: model)
            let kit = try await WhisperKit(model: modelPath.path)
            self.whisperKit = kit
            print("WhisperKit ready with model: \(model)")
        } catch {
            print("WhisperKit setup failed: \(error)")
        }
    }
    
    func transcribe(audioURL: URL) async -> String {
        guard let whisperKit = whisperKit else { return "WhisperKit not ready" }
        
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
