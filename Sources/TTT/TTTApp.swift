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
            let rawText = await whisper.transcribe(audioURL: audioURL)
            
            guard !rawText.isEmpty else {
                statusMessage = "文字起こし失敗"
                isProcessing = false
                return
            }
            
            statusMessage = "AI成形中 (\(network.isOnline ? "Groq" : "Bonsai"))..."
            
            let processedText: String
            if network.isOnline {
                processedText = await groq.processText(rawText, apiKey: settings.groqApiKey, prompt: settings.systemPrompt)
            } else {
                processedText = await bonsai.processText(rawText, prompt: settings.systemPrompt)
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

@main
struct TTTApp: App {
    @StateObject private var coordinator = TTTCoordinator()
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        // メインのメニューバーUI
        MenuBarExtra {
            Text("TTT (Talk to Type)")
            Text("ステータス: \(coordinator.statusMessage)")
            Divider()
            
            Button(coordinator.recorder.isRecording ? "録音停止" : "録音開始") {
                Task { await coordinator.toggleRecording() }
            }
            .keyboardShortcut("V", modifiers: [.command, .option])
            
            if coordinator.isProcessing {
                ProgressView("AI処理中...")
                    .padding(.horizontal)
            }
            
            Divider()
            
            Button("設定...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            
            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            HStack {
                Image(systemName: coordinator.recorder.isRecording ? "record.circle.fill" : (coordinator.isProcessing ? "cpu" : "waveform"))
                if coordinator.recorder.isRecording {
                    Text("REC")
                } else {
                    Text("TTT")
                }
            }
        }
        
        // 設定ウィンドウの定義
        Window("TTT 設定", id: "settings") {
            SettingsView(settings: coordinator.settings, accessibility: coordinator.accessibility)
        }
        .windowResizability(.contentSize)
    }
}
