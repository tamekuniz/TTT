import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

@MainActor
class TTTCoordinator: ObservableObject {
    @Published var recorder = AudioRecorder()
    @Published var whisper = WhisperManager()
    @Published var groq = GroqManager()
    @Published var bonsai = BonsaiManager()
    @Published var accessibility = AccessibilityManager()
    @Published var network = NetworkManager()
    @Published var settings = SettingsManager()
    
    @Published var statusMessage = "待機中"
    @Published var isProcessing = false
    
    init() {
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                await self?.toggleRecording()
            }
        }
    }
    
    func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            statusMessage = "文字起こし中..."
            isProcessing = true
            
            let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
            
            // 1. Whisper による文字起こし (素の状態)
            var rawText = await whisper.transcribe(audioURL: audioURL)
            
            guard !rawText.isEmpty else {
                statusMessage = "文字起こし失敗"
                isProcessing = false
                return
            }
            
            // 2. AI に渡す前の「事前置換」
            // 辞書の読みがあれば、AI に渡す前に正式名称に直して AI の精度を上げる
            for entry in settings.dictionary where !entry.reading.isEmpty {
                rawText = rawText.replacingOccurrences(of: entry.reading, with: entry.word)
            }
            
            statusMessage = "AI成形中 (\(network.isOnline ? "Groq" : "Bonsai"))..."
            
            // 3. AI による成形 (コンテキストは最小限)
            var processedText: String
            if network.isOnline {
                processedText = await groq.processText(rawText, apiKey: settings.groqApiKey, prompt: settings.systemPrompt)
            } else {
                processedText = await bonsai.processText(rawText, prompt: settings.systemPrompt)
            }
            
            // 4. AI 成形後の「事後置換」
            // 万が一 AI が読みを復活させたり誤変換した場合に備えて、もう一度強制修正
            for entry in settings.dictionary where !entry.reading.isEmpty {
                processedText = processedText.replacingOccurrences(of: entry.reading, with: entry.word)
            }
            
            statusMessage = "テキスト入力中..."
            accessibility.insertText(processedText)
            
            statusMessage = "完了"
            isProcessing = false
        } else {
            do {
                _ = try recorder.startRecording()
                statusMessage = "録音中..."
            } catch {
                statusMessage = "録音エラー: \(error.localizedDescription)"
            }
        }
    }
}
