import AppKit
import Combine
import SwiftUI
import KeyboardShortcuts
import os

extension KeyboardShortcuts.Name {
    static let triggerRecording = Self("triggerRecording")
}

@MainActor
class TypeToTalkCoordinator: ObservableObject {
    /// メニューバー UI 用のアプリ全体ステータス。
    /// Phase 1 では値を保持・更新するだけ（アイコン側はまだ静的）。
    /// Phase 2 で `MenuBarLabel` 側がこの値に追従してアイコンを切替える。
    enum AppStatus: Equatable {
        case idle
        case recording
        case processing
        case error(String)
    }

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
    @Published private(set) var formatterStatusText: String = "未読込"

    /// Phase 1 で追加。MenuBarExtra 用のステータス。
    /// 既存の `statusMessage` 文字列とは別系統で並行運用する。
    @Published var currentStatus: AppStatus = .idle

    private var isTriggerShortcutPressed = false
    private var isRightOptionPressed = false
    private var startupLoadTask: Task<Void, Never>?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.tamekuniz.TypeToTalk", category: "Coordinator")

    init() {
        let settings = SettingsManager()
        self.settings = settings
        self.whisper = WhisperManager(settings: settings)
        self.bonsai.configureSelectedModel(settings.resolvedBonsaiModelID)
        setupRightOptionMonitor()
        setupFormatterStatusBindings()

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

        // 依存元の現在値で初期表示を確定する
        refreshFormatterStatusText()
    }

    /// formatterStatusText を活性 provider と依存元の状態から計算して @Published に反映する。
    /// View 再評価のトリガを「Coordinator の @Published 変化」に揃えるため、計算結果は必ず
    /// プロパティ代入経由で公開する（計算型プロパティで包むと objectWillChange が発火せず、
    /// メインウインドウへ伝播しない）。
    private func refreshFormatterStatusText() {
        let newValue: String
        switch activeFormatterProvider {
        case .groq, .openAI:
            newValue = network.isOnline ? "準備完了" : "未接続"
        case .bonsai:
            newValue = bonsai.statusMessage
        }
        if formatterStatusText != newValue {
            formatterStatusText = newValue
        }
    }

    /// formatterStatusText の依存元（bonsai.statusMessage / network.isOnline /
    /// settings の formatter / Bonsai modelID 関連）を Combine で購読し、
    /// 変化があるたびに refreshFormatterStatusText() を呼ぶ。
    private func setupFormatterStatusBindings() {
        bonsai.$statusMessage
            .sink { [weak self] _ in self?.refreshFormatterStatusText() }
            .store(in: &cancellables)

        network.$isOnline
            .sink { [weak self] _ in self?.refreshFormatterStatusText() }
            .store(in: &cancellables)

        settings.$formatterProviderRawValue
            .sink { [weak self] _ in self?.refreshFormatterStatusText() }
            .store(in: &cancellables)

        settings.$bonsaiModelPresetRawValue
            .sink { [weak self] _ in self?.refreshFormatterStatusText() }
            .store(in: &cancellables)

        settings.$bonsaiCustomModelID
            .sink { [weak self] _ in self?.refreshFormatterStatusText() }
            .store(in: &cancellables)
    }

    func handleAppLaunch() {
        startupLoadTask?.cancel()
        startupLoadTask = Task { @MainActor [weak self] in
            await self?.synchronizeModelsForCurrentSettings()
            self?.currentStatus = .idle
        }
    }

    func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            performHapticFeedback(.levelChange)
            statusMessage = "文字起こし中..."
            isProcessing = true
            currentStatus = .processing

            guard let audioURL = recordingURL else {
                statusMessage = "録音ファイルが見つかりません"
                isProcessing = false
                currentStatus = .error("録音ファイルが見つかりません")
                return
            }

            guard whisper.whisperKit != nil else {
                statusMessage = "聞き取りモデルを読み込んでください"
                isProcessing = false
                currentStatus = .error("聞き取りモデル未読込")
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
                currentStatus = .error("文字起こし失敗")
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
                performHapticFeedback(.alignment)
                currentStatus = .idle
            case .missingPermission:
                statusMessage = "アクセシビリティ権限が必要です（テキスト入力に必要）"
                showAccessibilityPermissionAlert = true
                currentStatus = .error("アクセシビリティ権限なし")
            case .noFocusedElement:
                statusMessage = "入力先が見つかりません"
                currentStatus = .error("入力先なし")
            case .unsupportedTarget:
                statusMessage = "この入力欄には書き込めません"
                currentStatus = .error("書込不可")
            }
            isProcessing = false
        } else {
            do {
                await synchronizeModelsForCurrentSettings()
                recordingURL = try await recorder.startRecording()
                performHapticFeedback(.generic)
                statusMessage = "録音中..."
                currentStatus = .recording
            } catch {
                statusMessage = "録音エラー: \(error.localizedDescription)"
                currentStatus = .error("録音エラー")
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
            await toggleRecording()
        case .pushToTalk:
            if !recorder.isRecording && !isProcessing {
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

    private func performHapticFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
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

    var isFormatterLoading: Bool {
        activeFormatterProvider == .bonsai && bonsai.isLoadingModel
    }

    /// アプリを再起動する。新しいプロセスを openApplication で起動してから自身を terminate する。
    /// 主用途: アクセシビリティ権限の AXIsProcessTrusted キャッシュを破棄するため。
    func restartApp() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: config,
            completionHandler: { _, error in
                DispatchQueue.main.async {
                    if error == nil {
                        NSApp.terminate(nil)
                    }
                    // error 時は terminate しない（ユーザーが手動でリトライ可能）
                }
            }
        )
    }

    func synchronizeModelsForCurrentSettings() async {
        let bonsaiModelID = settings.resolvedBonsaiModelID
        let provider = activeFormatterProvider
        logger.debug("synchronizeModels: provider=\(String(describing: provider), privacy: .public) bonsaiModelID=\(bonsaiModelID, privacy: .public)")

        await whisper.ensureSelectedModelLoaded()
        bonsai.configureSelectedModel(bonsaiModelID)

        guard provider == .bonsai else {
            logger.debug("synchronizeModels: skip Bonsai autoload (provider != .bonsai)")
            return
        }
        await bonsai.ensureSelectedModelLoaded(modelID: bonsaiModelID)
        // 自動ロード結果は loadState/statusMessage 経由で sink され、
        // formatterStatusText に反映される（refreshFormatterStatusText）。
        refreshFormatterStatusText()
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

/// MenuBarExtra の label 部分。
/// Phase 1 では SF Symbol 固定（`mic.circle`）。
/// 旧 `WindowGroup { TypeToTalkMainView ... .onAppear / .onChange(...) }` で行っていた
/// 起動時セットアップと Combine 的な再構成トリガを、ここに移植する。
/// （Settings ウインドウは独立した Scene なので、起動直後は表示されない。
///   MenuBarExtra の label は起動時に必ず一度描画されるため、そこを起動フックとして使う。）
struct MenuBarLabel: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var didLaunch = false

    var body: some View {
        Image(systemName: "mic.circle")
            .onAppear {
                if !didLaunch {
                    didLaunch = true
                    coordinator.handleAppLaunch()
                }
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
            .onChange(of: scenePhase) { _, newPhase in
                // フォアグラウンド復帰時に権限状態を最新化（システム設定で変更後の反映）
                if newPhase == .active {
                    coordinator.accessibility.refreshPermissionStatus()
                }
            }
    }
}

@main
struct TypeToTalkApp: App {
    @StateObject private var coordinator = TypeToTalkCoordinator()

    init() {
        // メニューバー常駐型（Dock 非表示）。Scene 構成より前に確定させる。
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            SettingsLink {
                Text("設定...")
            }
            Divider()
            Button("TypeToTalk を終了") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            MenuBarLabel(coordinator: coordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settings: coordinator.settings,
                whisper: coordinator.whisper,
                bonsai: coordinator.bonsai,
                accessibility: coordinator.accessibility,
                coordinator: coordinator
            )
        }
    }
}
