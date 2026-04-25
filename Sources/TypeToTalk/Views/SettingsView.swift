import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var whisper: WhisperManager
    @ObservedObject var bonsai: BonsaiManager
    @ObservedObject var accessibility: AccessibilityManager
    
    @State private var newWord = ""
    @State private var newReading = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabView {
                generalSettings
                    .tabItem {
                        Label("一般", systemImage: "gearshape")
                    }
                
                dictionarySettings
                    .tabItem {
                        Label("スマート辞書", systemImage: "text.book.closed")
                    }
            }
            
            HStack {
                Spacer()
                Text(appVersionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }
    
    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("聞き取りAI") {
                            Picker("聞き取りAI", selection: $settings.transcriptionProviderRawValue) {
                                ForEach(TranscriptionProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        settingRow("聞き取りモデル") {
                            Picker("聞き取りモデル", selection: $settings.whisperModelPresetRawValue) {
                                ForEach(WhisperModelPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        if settings.whisperModelPreset == .custom {
                            settingRow("モデルID") {
                                TextField("Whisper モデル ID", text: $settings.whisperCustomModelID)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        loadStatusBlock(
                            status: whisper.statusText,
                            loadedModel: whisper.loadedModelDisplayName,
                            selectedModel: whisper.needsExplicitLoad ? whisper.selectedModelDisplayName : nil,
                            buttonTitle: whisper.isLoadingModel ? "再読込中..." : "再読込",
                            isDisabled: whisper.isLoadingModel || !whisper.needsExplicitLoad
                        ) {
                            Task {
                                await whisper.loadSelectedModel()
                            }
                        }
                        
                        Text("選択した Whisper モデルをローカルにダウンロードして使います。`推奨モデル` はこの Mac に合う既定の variant を自動選択します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    sectionTitle("聞き取り設定", subtitle: "音声を文字に起こすモデル")
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("整形AI") {
                            Picker("整形AI", selection: $settings.formatterProviderRawValue) {
                                ForEach(FormatterProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        if settings.formatterProvider == .groq {
                            settingRow("APIキー") {
                                SecureField("Groq API キー", text: $settings.groqApiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            settingRow("モデル") {
                                TextField("Groq モデル", text: $settings.groqModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        if settings.formatterProvider == .openAI {
                            settingRow("APIキー") {
                                SecureField("OpenAI API キー", text: $settings.openAIApiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            settingRow("モデル") {
                                TextField("OpenAI モデル", text: $settings.openAIModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        if settings.formatterProvider == .bonsai {
                            settingRow("ローカルモデル") {
                                Picker("ローカルモデル", selection: $settings.bonsaiModelPresetRawValue) {
                                    ForEach(BonsaiModelPreset.allCases) { preset in
                                        Text(preset.displayName).tag(preset.rawValue)
                                    }
                                }
                                .labelsHidden()
                            }
                            
                            if settings.bonsaiModelPreset == .custom {
                                settingRow("モデルID") {
                                    TextField("Hugging Face モデル ID", text: $settings.bonsaiCustomModelID)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            
                            loadStatusBlock(
                                status: bonsai.statusMessage,
                                loadedModel: bonsai.loadedModelDisplayName,
                                selectedModel: bonsai.needsExplicitLoad ? settings.resolvedBonsaiModelID : nil,
                                buttonTitle: bonsai.isLoadingModel ? "再読込中..." : "再読込",
                                isDisabled: bonsai.isLoadingModel || !bonsai.needsExplicitLoad
                            ) {
                                Task {
                                    await bonsai.loadSelectedModel(modelID: settings.resolvedBonsaiModelID)
                                }
                            }
                            
                                Text("初回利用時に `\(settings.resolvedBonsaiModelID)` をダウンロードし、`~/.typetotalk/models` 配下へキャッシュします。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("整形プロンプト")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $settings.systemPrompt)
                                .frame(minHeight: 90)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2))
                                )
                        }
                        
                        if settings.formatterProvider != .bonsai {
                            Text("ネットワーク未接続時は自動で Bonsai にフォールバックします。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    sectionTitle("整形設定", subtitle: "文字起こし後の補正と要約")
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("ショートカット") {
                            KeyboardShortcuts.Recorder(for: .triggerRecording)
                        }

                        settingRow("ウインドウ表示トグル") {
                            KeyboardShortcuts.Recorder(for: .toggleWindow)
                        }

                        settingRow("動作") {
                            Picker("トリガー動作", selection: $settings.shortcutTriggerModeRawValue) {
                                ForEach(ShortcutTriggerMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        Text("任意のショートカットに加えて、右 Option 単体でも録音を制御できます。トグルは押すたび開始/停止、プッシュトークは押している間だけ録音します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    sectionTitle("ショートカット", subtitle: "録音の開始方法")
                }
                
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("アクセシビリティ権限")
                            Text("テキストを直接入力するために必要です。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: accessibility.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibility.hasPermission ? .green : .orange)
                        Button(accessibility.hasPermission ? "許可済み" : "設定を開く") {
                            if !accessibility.hasPermission {
                                accessibility.requestPermission()
                                accessibility.openAccessibilitySettings()
                            }
                        }
                        .disabled(accessibility.hasPermission)
                    }
                } label: {
                    sectionTitle("システム権限", subtitle: "入力に必要な macOS 権限")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var dictionarySettings: some View {
        VStack {
            Text("よく使う専門用語や人名を登録すると、聞き取り精度が向上し、自動的に置換されます。コンテキスト（文脈）を汚さず高速に動作します。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            
            List {
                ForEach(settings.dictionary) { entry in
                    HStack {
                        Text(entry.word)
                            .fontWeight(.bold)
                        Spacer()
                        Text(entry.reading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: settings.removeEntry)
            }
            .listStyle(.bordered)
            
            HStack {
                TextField("単語 (例: TypeToTalk)", text: $newWord)
                TextField("よみ (例: てぃーてぃーてぃー)", text: $newReading)
                Button("追加") {
                    if !newWord.isEmpty {
                        settings.addEntry(word: newWord, reading: newReading)
                        newWord = ""
                        newReading = ""
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            content()
        }
    }
    
    @ViewBuilder
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func loadStatusBlock(
        status: String,
        loadedModel: String,
        selectedModel: String?,
        buttonTitle: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("状態: \(status)")
                Text("現在の読込モデル: \(loadedModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let selectedModel {
                    Text("選択中のモデル: `\(selectedModel)`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button(buttonTitle, action: action)
                .disabled(isDisabled)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let buildNumber = info["CFBundleVersion"] as? String ?? "-"
        return "Version \(shortVersion) (\(buildNumber))"
    }
}
