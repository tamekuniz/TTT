import AppKit
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let triggerRecording = Self("triggerRecording")
    static let toggleWindow = Self("toggleWindow")
}

struct TypeToTalkMainView: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator
    
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TypeToTalk")
                        .font(.title3.weight(.semibold))
                    if !coordinator.statusMessage.isEmpty {
                        Text(coordinator.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 56)
            
            Button {
                Task {
                    await coordinator.toggleRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(micButtonColor)
                        .frame(width: 88, height: 88)
                    Image(systemName: coordinator.recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isProcessing)
            
            VStack(spacing: 10) {
                modelStatusRow(
                    title: "Whisper",
                    detail: coordinator.settings.whisperDisplayName,
                    status: coordinator.whisper.statusText
                )
                modelStatusRow(
                    title: "Formatter",
                    detail: coordinator.activeFormatterDisplayName,
                    status: coordinator.activeFormatterStatusText
                )
                Text("ショートカットで呼び出すと、このダイアログを前面に出します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(width: 360, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(10)
        .alert("アクセシビリティ権限が必要です", isPresented: $coordinator.showAccessibilityPermissionAlert) {
            Button("システム設定を開く") {
                coordinator.accessibility.openAccessibilitySettings()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("TypeToTalk が文字起こし結果をフォーカス中の入力欄に書き込むには、アクセシビリティ権限が必要です。\n\nシステム設定 → プライバシーとセキュリティ → アクセシビリティ で TypeToTalk を有効にしてください。")
        }
    }

    private var micButtonColor: Color {
        if coordinator.recorder.isRecording {
            return .red
        }

        if coordinator.whisper.whisperKit != nil {
            return Color(red: 0.10, green: 0.47, blue: 0.95)
        }

        return Color(red: 0.45, green: 0.83, blue: 0.98)
    }
    
    private func modelStatusRow(
        title: String,
        detail: String,
        status: String
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.subheadline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                statusBadge(status)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
    }

    private func statusBadge(_ value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(for: value))
                .frame(width: 8, height: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }

    private func statusColor(for value: String) -> Color {
        if value.contains("準備完了") || value.contains("完了") {
            return Color(red: 0.18, green: 0.67, blue: 0.37)
        }

        if value.contains("読込中") || value.contains("録音中") {
            return Color(red: 0.95, green: 0.64, blue: 0.16)
        }

        if value.contains("失敗") || value.contains("未接続") || value.contains("未読込") {
            return Color(red: 0.77, green: 0.42, blue: 0.18)
        }

        return Color.secondary.opacity(0.7)
    }
}

@MainActor
class TypeToTalkCoordinator: ObservableObject {
    @Published var recorder = AudioRecorder()
    @Published var whisper: WhisperManager
    @Published var formatter = OpenAICompatibleManager()
    @Published var bonsai = BonsaiManager()
    @Published var accessibility = AccessibilityManager()
    @Published var network = NetworkManager()
    @Published var settings: SettingsManager
    
    @Published var statusMessage = ""
    @Published var isProcessing = false
    @Published var lastTriggerSource = "未検出"
    @Published var showAccessibilityPermissionAlert = false
    @Published private(set) var recordingURL: URL?
    
    private var isTriggerShortcutPressed = false
    private var isRightOptionPressed = false
    private var startupLoadTask: Task<Void, Never>?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    
    init() {
        let settings = SettingsManager()
        self.settings = settings
        self.whisper = WhisperManager(settings: settings)
        self.bonsai.configureSelectedModel(settings.resolvedBonsaiModelID)
        setupRightOptionMonitor()
        
        KeyboardShortcuts.onKeyDown(for: .triggerRecording) { [weak self] in
            Task { @MainActor in
                await self?.handleTriggerShortcutDown()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .triggerRecording) { [weak self] in
            Task { @MainActor in
                await self?.handleTriggerShortcutUp()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleWindow) { [weak self] in
            Task { @MainActor in
                self?.handleToggleWindow()
            }
        }
    }

    func handleAppLaunch() {
        startupLoadTask?.cancel()
        startupLoadTask = Task { @MainActor [weak self] in
            await self?.synchronizeModelsForCurrentSettings()
        }
    }

    func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            statusMessage = "文字起こし中..."
            isProcessing = true

            guard let audioURL = recordingURL else {
                statusMessage = "録音ファイルが見つかりません"
                isProcessing = false
                return
            }

            guard whisper.whisperKit != nil else {
                statusMessage = "聞き取りモデルを読み込んでください"
                isProcessing = false
                return
            }
            
            // 1. Whisper による文字起こし (素の状態)
            var rawText = await whisper.transcribe(
                audioURL: audioURL,
                language: settings.whisperLanguage
            )
            
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
            
            // 3. AI による成形 (コンテキストは最小限)
            let activeFormatter = activeFormatterProvider
            statusMessage = "AI成形中 (\(activeFormatterDisplayName))..."
            let processedText = await processText(rawText, with: activeFormatter)
            
            // 4. AI 成形後の「事後置換」
            // 万が一 AI が読みを復活させたり誤変換した場合に備えて、もう一度強制修正
            var finalText = processedText
            for entry in settings.dictionary where !entry.reading.isEmpty {
                finalText = finalText.replacingOccurrences(of: entry.reading, with: entry.word)
            }
            
            statusMessage = "テキスト入力中..."
            switch accessibility.insertText(finalText) {
            case .success:
                statusMessage = "完了"
            case .missingPermission:
                statusMessage = "アクセシビリティ権限が必要です（テキスト入力に必要）"
                showAccessibilityPermissionAlert = true
            case .noFocusedElement:
                statusMessage = "入力先が見つかりません"
            case .unsupportedTarget:
                statusMessage = "この入力欄には書き込めません"
            }
            isProcessing = false
        } else {
            do {
                await synchronizeModelsForCurrentSettings()
                recordingURL = try await recorder.startRecording()
                statusMessage = "録音中..."
            } catch {
                statusMessage = "録音エラー: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleTriggerShortcutDown() async {
        guard !isTriggerShortcutPressed else { return }
        isTriggerShortcutPressed = true
        recordTriggerFeedback(source: "グローバル")
        
        switch settings.shortcutTriggerMode {
        case .disabled:
            break
        case .toggle:
            showRecorderWindow()
            await toggleRecording()
        case .pushToTalk:
            if !recorder.isRecording && !isProcessing {
                showRecorderWindow()
                await toggleRecording()
            }
        }
    }
    
    private func handleTriggerShortcutUp() async {
        guard isTriggerShortcutPressed else { return }
        isTriggerShortcutPressed = false
        
        guard settings.shortcutTriggerMode == .pushToTalk else { return }
        guard recorder.isRecording else { return }
        
        await toggleRecording()
    }

    private func setupRightOptionMonitor() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                await self?.handleFlagsChanged(event)
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                await self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) async {
        guard event.keyCode == 61 else { return }

        let isPressed = event.modifierFlags.contains(.option)
        guard isPressed != isRightOptionPressed else { return }

        isRightOptionPressed = isPressed

        if isPressed {
            recordTriggerFeedback(source: "右Option")
            await handleTriggerShortcutDown()
        } else {
            await handleTriggerShortcutUp()
        }
    }

    private func recordTriggerFeedback(source: String) {
        lastTriggerSource = source
        if !recorder.isRecording && !isProcessing {
            statusMessage = "\(source) を受信"
        }
        NSSound.beep()
    }
    
    private var activeFormatterProvider: FormatterProvider {
        let selected = settings.formatterProvider
        if selected.requiresNetwork && !network.isOnline {
            return .bonsai
        }
        return selected
    }
    
    var activeFormatterDisplayName: String {
        let provider = activeFormatterProvider
        switch provider {
        case .groq, .openAI:
            return provider.displayName
        case .bonsai:
            return settings.bonsaiDisplayName
        }
    }
    
    var activeFormatterStatusText: String {
        switch activeFormatterProvider {
        case .groq, .openAI:
            return network.isOnline ? "準備完了" : "未接続"
        case .bonsai:
            return bonsai.statusMessage
        }
    }

    var isFormatterLoading: Bool {
        activeFormatterProvider == .bonsai && bonsai.isLoadingModel
    }
    
    func showRecorderWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            if window.identifier?.rawValue == "RecorderWindow" {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
    }

    private func handleToggleWindow() {
        let recorderWindow = NSApplication.shared.windows.first { window in
            window.identifier?.rawValue == "RecorderWindow"
        }

        guard let window = recorderWindow else {
            // ウインドウが未生成の場合は表示する（フォールバック）
            showRecorderWindow()
            return
        }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func synchronizeModelsForCurrentSettings() async {
        await whisper.ensureSelectedModelLoaded()
        bonsai.configureSelectedModel(settings.resolvedBonsaiModelID)

        guard activeFormatterProvider == .bonsai else { return }
        await bonsai.ensureSelectedModelLoaded(modelID: settings.resolvedBonsaiModelID)
    }
    
    private func processText(_ text: String, with provider: FormatterProvider) async -> String {
        let prompt: String
        if settings.promptMode == "preset" {
            prompt = settings.systemPromptForLanguageAndStyle(
                language: settings.formatterLanguage,
                style: settings.textStyle,
                provider: provider
            )
        } else {
            prompt = settings.systemPrompt
        }

        switch provider {
        case .groq:
            return await formatter.processText(
                text,
                endpoint: "https://api.groq.com/openai/v1/chat/completions",
                model: settings.groqModel,
                apiKey: settings.groqApiKey,
                prompt: prompt
            )
        case .openAI:
            return await formatter.processText(
                text,
                endpoint: "https://api.openai.com/v1/chat/completions",
                model: settings.openAIModel,
                apiKey: settings.openAIApiKey,
                prompt: prompt
            )
        case .bonsai:
            bonsai.configureSelectedModel(settings.resolvedBonsaiModelID)
            return await bonsai.processText(
                text,
                prompt: prompt,
                modelID: settings.resolvedBonsaiModelID
            )
        }
    }
}

@main
struct TypeToTalkApp: App {
    @StateObject private var coordinator = TypeToTalkCoordinator()
    
    var body: some Scene {
        WindowGroup {
            TypeToTalkMainView(coordinator: coordinator)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.identifier = NSUserInterfaceItemIdentifier("RecorderWindow")
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.isMovableByWindowBackground = true
                    }
                    coordinator.handleAppLaunch()
                }
                .onChange(of: coordinator.settings.formatterProviderRawValue) { _, _ in
                    coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
                }
                .onChange(of: coordinator.settings.bonsaiModelPresetRawValue) { _, _ in
                    coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
                }
                .onChange(of: coordinator.settings.bonsaiCustomModelID) { _, _ in
                    coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView(
                settings: coordinator.settings,
                whisper: coordinator.whisper,
                bonsai: coordinator.bonsai,
                accessibility: coordinator.accessibility
            )
        }
    }
}
