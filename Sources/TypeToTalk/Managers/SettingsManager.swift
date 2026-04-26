import Foundation

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case whisperKit
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .whisperKit:
            return "WhisperKit (ローカル)"
        }
    }
}

enum WhisperModelPreset: String, CaseIterable, Identifiable {
    case recommended
    case tiny
    case base
    case small
    case largeV3
    case largeV3Turbo
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .recommended:
            return "推奨モデル"
        case .tiny:
            return "Whisper Tiny"
        case .base:
            return "Whisper Base"
        case .small:
            return "Whisper Small"
        case .largeV3:
            return "Whisper Large v3"
        case .largeV3Turbo:
            return "Whisper Large v3 Turbo"
        case .custom:
            return "カスタム Whisper モデル"
        }
    }
    
    var modelID: String? {
        switch self {
        case .recommended:
            return nil
        case .tiny:
            return "openai_whisper-tiny"
        case .base:
            return "openai_whisper-base"
        case .small:
            return "openai_whisper-small"
        case .largeV3:
            return "openai_whisper-large-v3"
        case .largeV3Turbo:
            return "openai_whisper-large-v3_turbo"
        case .custom:
            return nil
        }
    }
}

enum FormatterProvider: String, CaseIterable, Identifiable {
    case groq
    case openAI
    case bonsai
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .groq:
            return "Groq"
        case .openAI:
            return "OpenAI"
        case .bonsai:
            return "Ternary Bonsai (ローカル)"
        }
    }
    
    var requiresNetwork: Bool {
        switch self {
        case .groq, .openAI:
            return true
        case .bonsai:
            return false
        }
    }
}

enum BonsaiModelPreset: String, CaseIterable, Identifiable {
    case ternaryBonsai8B2bit
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ternaryBonsai8B2bit:
            return "Ternary Bonsai 8B 2-bit"
        case .custom:
            return "カスタム Hugging Face モデル"
        }
    }
    
    var modelID: String? {
        switch self {
        case .ternaryBonsai8B2bit:
            return "prism-ml/Ternary-Bonsai-8B-mlx-2bit"
        case .custom:
            return nil
        }
    }
}

enum ShortcutTriggerMode: String, CaseIterable, Identifiable {
    case disabled
    case toggle
    case pushToTalk
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .disabled:
            return "使わない"
        case .toggle:
            return "トグル"
        case .pushToTalk:
            return "プッシュトーク"
        }
    }
}

@MainActor
class SettingsManager: ObservableObject {
    @Published var transcriptionProviderRawValue: String {
        didSet { UserDefaults.standard.set(transcriptionProviderRawValue, forKey: "transcriptionProvider") }
    }
    
    @Published var whisperModelPresetRawValue: String {
        didSet { UserDefaults.standard.set(whisperModelPresetRawValue, forKey: "whisperModelPreset") }
    }
    
    @Published var whisperCustomModelID: String {
        didSet { UserDefaults.standard.set(whisperCustomModelID, forKey: "whisperCustomModelID") }
    }
    
    @Published var formatterProviderRawValue: String {
        didSet { UserDefaults.standard.set(formatterProviderRawValue, forKey: "formatterProvider") }
    }
    
    @Published var groqApiKey: String {
        didSet { UserDefaults.standard.set(groqApiKey, forKey: "groqApiKey") }
    }
    
    @Published var groqModel: String {
        didSet { UserDefaults.standard.set(groqModel, forKey: "groqModel") }
    }
    
    @Published var openAIApiKey: String {
        didSet { UserDefaults.standard.set(openAIApiKey, forKey: "openAIApiKey") }
    }
    
    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "openAIModel") }
    }
    
    @Published var bonsaiModelPresetRawValue: String {
        didSet { UserDefaults.standard.set(bonsaiModelPresetRawValue, forKey: "bonsaiModelPreset") }
    }
    
    @Published var bonsaiCustomModelID: String {
        didSet { UserDefaults.standard.set(bonsaiCustomModelID, forKey: "bonsaiCustomModelID") }
    }
    
    @Published var shortcutTriggerModeRawValue: String {
        didSet { UserDefaults.standard.set(shortcutTriggerModeRawValue, forKey: "shortcutTriggerMode") }
    }
    
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }

    /// 聞き取り言語コード（"ja" / "en" / "auto"）。WhisperKit の DecodingOptions.language に渡す。
    /// "auto" のときは language を渡さず detectLanguage = true で自動検出する。
    @Published var whisperLanguage: String {
        didSet { UserDefaults.standard.set(whisperLanguage, forKey: "whisperLanguage") }
    }

    /// 整形 AI のターゲット言語コード（"ja" / "en"）。systemPromptForLanguageAndStyle のテンプレート選択に使う。
    @Published var formatterLanguage: String {
        didSet { UserDefaults.standard.set(formatterLanguage, forKey: "formatterLanguage") }
    }

    /// 整形時の文体（"desuMasu" / "daDearu" / "auto"）。英語時は無視される。
    @Published var textStyle: String {
        didSet { UserDefaults.standard.set(textStyle, forKey: "textStyle") }
    }

    /// プロンプトモード（"preset" / "custom"）。
    /// 既存ユーザーが編集した systemPrompt を温存するため初期値は "custom"。
    @Published var promptMode: String {
        didSet { UserDefaults.standard.set(promptMode, forKey: "promptMode") }
    }

    /// 録音開始/停止時のフィードバック音 ON/OFF。デフォルト ON（true）。
    /// OFF 時は触覚フィードバックのみ発火し、システム音（Tink/Pop）は鳴らさない。
    @Published var soundFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled") }
    }

    /// 録音中・処理中の視覚フィードバック HUD ON/OFF。デフォルト ON（true）。
    /// OFF 時は HUD パネル（画面下中央）が一切表示されない。
    @Published var visualFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(visualFeedbackEnabled, forKey: "visualFeedbackEnabled") }
    }

    @Published var dictionary: [DictionaryEntry] {
        didSet {
            if let encoded = try? JSONEncoder().encode(dictionary) {
                UserDefaults.standard.set(encoded, forKey: "userDictionary")
            }
        }
    }
    
    init() {
        self.transcriptionProviderRawValue = UserDefaults.standard.string(forKey: "transcriptionProvider") ?? TranscriptionProvider.whisperKit.rawValue
        self.whisperModelPresetRawValue = UserDefaults.standard.string(forKey: "whisperModelPreset") ?? WhisperModelPreset.recommended.rawValue
        self.whisperCustomModelID = UserDefaults.standard.string(forKey: "whisperCustomModelID") ?? ""
        self.formatterProviderRawValue = UserDefaults.standard.string(forKey: "formatterProvider") ?? FormatterProvider.groq.rawValue
        self.groqApiKey = UserDefaults.standard.string(forKey: "groqApiKey") ?? ""
        self.groqModel = UserDefaults.standard.string(forKey: "groqModel") ?? "llama3-8b-8192"
        self.openAIApiKey = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
        self.openAIModel = UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4o-mini"
        self.bonsaiModelPresetRawValue = UserDefaults.standard.string(forKey: "bonsaiModelPreset") ?? BonsaiModelPreset.ternaryBonsai8B2bit.rawValue
        self.bonsaiCustomModelID = UserDefaults.standard.string(forKey: "bonsaiCustomModelID") ?? ""
        self.shortcutTriggerModeRawValue =
            UserDefaults.standard.string(forKey: "shortcutTriggerMode") ??
            UserDefaults.standard.string(forKey: "rightOptionMode") ??
            ShortcutTriggerMode.disabled.rawValue
        self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? "以下の文字起こしテキストを、自然な日本語に修正してください。不要なフィラーは削除し、文脈を整えてください。"
        self.whisperLanguage = UserDefaults.standard.string(forKey: "whisperLanguage") ?? "ja"
        self.formatterLanguage = UserDefaults.standard.string(forKey: "formatterLanguage") ?? "ja"
        self.textStyle = UserDefaults.standard.string(forKey: "textStyle") ?? "auto"
        self.promptMode = UserDefaults.standard.string(forKey: "promptMode") ?? "custom"

        // soundFeedbackEnabled: 未設定時は true（デフォルト ON）
        // bool(forKey:) は未設定で false を返すため、object(forKey:) で存在チェックする
        if UserDefaults.standard.object(forKey: "soundFeedbackEnabled") != nil {
            self.soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
        } else {
            self.soundFeedbackEnabled = true
        }

        // visualFeedbackEnabled: 未設定時は true（デフォルト ON）
        if UserDefaults.standard.object(forKey: "visualFeedbackEnabled") != nil {
            self.visualFeedbackEnabled = UserDefaults.standard.bool(forKey: "visualFeedbackEnabled")
        } else {
            self.visualFeedbackEnabled = true
        }

        if let data = UserDefaults.standard.data(forKey: "userDictionary"),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            self.dictionary = decoded
        } else {
            // 初期サンプル
            self.dictionary = [
                DictionaryEntry(word: "TypeToTalk", reading: "タイプトゥートーク"),
                DictionaryEntry(word: "tamekuniz", reading: "ためくにず")
            ]
        }
    }
    
    var transcriptionProvider: TranscriptionProvider {
        get { TranscriptionProvider(rawValue: transcriptionProviderRawValue) ?? .whisperKit }
        set { transcriptionProviderRawValue = newValue.rawValue }
    }
    
    var whisperModelPreset: WhisperModelPreset {
        get { WhisperModelPreset(rawValue: whisperModelPresetRawValue) ?? .recommended }
        set { whisperModelPresetRawValue = newValue.rawValue }
    }
    
    var formatterProvider: FormatterProvider {
        get { FormatterProvider(rawValue: formatterProviderRawValue) ?? .groq }
        set { formatterProviderRawValue = newValue.rawValue }
    }
    
    var bonsaiModelPreset: BonsaiModelPreset {
        get { BonsaiModelPreset(rawValue: bonsaiModelPresetRawValue) ?? .ternaryBonsai8B2bit }
        set { bonsaiModelPresetRawValue = newValue.rawValue }
    }
    
    var shortcutTriggerMode: ShortcutTriggerMode {
        get { ShortcutTriggerMode(rawValue: shortcutTriggerModeRawValue) ?? .disabled }
        set { shortcutTriggerModeRawValue = newValue.rawValue }
    }
    
    var resolvedBonsaiModelID: String {
        if let presetModelID = bonsaiModelPreset.modelID {
            return presetModelID
        }
        let trimmed = bonsaiCustomModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "prism-ml/Ternary-Bonsai-8B-mlx-2bit" : trimmed
    }
    
    var resolvedWhisperModelID: String? {
        if let presetModelID = whisperModelPreset.modelID {
            return presetModelID
        }
        let trimmed = whisperCustomModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    var whisperDisplayName: String {
        switch whisperModelPreset {
        case .recommended:
            return "推奨モデル"
        case .custom:
            return resolvedWhisperModelID ?? "推奨モデル"
        default:
            return whisperModelPreset.displayName
        }
    }
    
    var bonsaiDisplayName: String {
        switch bonsaiModelPreset {
        case .ternaryBonsai8B2bit:
            return "Ternary Bonsai 8B"
        case .custom:
            return resolvedBonsaiModelID
        }
    }
    
    func addEntry(word: String, reading: String) {
        dictionary.append(DictionaryEntry(word: word, reading: reading))
    }
    
    func removeEntry(at offsets: IndexSet) {
        dictionary.remove(atOffsets: offsets)
    }

    /// 言語 × 文体 × プロバイダーの組み合わせから整形 AI 用 systemPrompt を組み立てる。
    ///
    /// - Parameters:
    ///   - language: "ja" / "en"。それ以外は ja として扱う。
    ///   - style: "desuMasu" / "daDearu" / "auto"。英語の場合は無視。
    ///   - provider: Bonsai は context window 配慮で軽量版（few-shot 1 例 / 簡素な記述）、
    ///               Groq・OpenAI は詳細版（few-shot 2 例 / 5 層構造）を返す。
    /// - Returns: system role に渡せる完成済みプロンプト文字列。
    func systemPromptForLanguageAndStyle(
        language: String,
        style: String,
        provider: FormatterProvider
    ) -> String {
        let normalizedLanguage = language == "en" ? "en" : "ja"
        let isLightweight = (provider == .bonsai)

        switch (normalizedLanguage, isLightweight) {
        case ("ja", true):
            return japaneseBonsaiPrompt(style: style)
        case ("ja", false):
            return japaneseDetailedPrompt(style: style)
        case ("en", true):
            return englishBonsaiPrompt()
        case ("en", false):
            return englishDetailedPrompt()
        default:
            return japaneseDetailedPrompt(style: style)
        }
    }

    private func japaneseStyleInstruction(_ style: String) -> String {
        switch style {
        case "desuMasu":
            return "ですます調で統一する"
        case "daDearu":
            return "だ・である調で統一する"
        default:
            return "入力の文体に合わせる"
        }
    }

    private func japaneseBonsaiPrompt(style: String) -> String {
        let styleLine = japaneseStyleInstruction(style)
        return """
        音声入力テキストの整形:
        - 誤字訂正、フィラー除去、言い直し統合
        - 文体: \(styleLine)
        - 出力: 整形後テキストのみ。前置き禁止
        """
    }

    private func japaneseDetailedPrompt(style: String) -> String {
        let styleLine = japaneseStyleInstruction(style)
        return """
        あなたは音声入力で得られたテキストを整形する編集者です。

        入力は Whisper による音声認識結果で、誤字・フィラー・言い直しを含む可能性があります。
        以下の整形ルールに従って、自然な文章に整形してください:

        - 同音異義語の誤字は文脈で訂正する
        - 「えーと」「あの」「まあ」等のフィラーを除去する
        - 「あ、違う」「いや」等の自己訂正を取り込んで最終形にする
        - 不要な句読点・記号を整理する
        - 文体: \(styleLine)

        出力は整形後のテキストのみを返してください。前置き、説明、マークダウン記法は禁止です。

        例:
        入力: えーと、明日の会議はあの、3時から、いや、4時からでお願いします。
        出力: 明日の会議は4時からでお願いします。

        入力: ご指摘の通り、修正版をお送りします。あ、違う、最新版でした。
        出力: ご指摘の通り、最新版をお送りします。
        """
    }

    private func englishBonsaiPrompt() -> String {
        return """
        Refine voice-to-text:
        - Fix typos, remove fillers, integrate corrections
        - Output: refined text only. No preamble.
        """
    }

    private func englishDetailedPrompt() -> String {
        return """
        You are an editor refining voice-to-text output.

        Input is Whisper transcription with potential typos, fillers, and self-corrections.
        Apply the following rules:

        - Correct homophone errors using context
        - Remove fillers ("um", "uh", "like", etc.)
        - Integrate self-corrections to final form
        - Clean up unnecessary punctuation
        - Style: Match input style

        Return only the refined text. No preamble, no explanation, no markdown.

        Example:
        Input: Um, the meeting is at, like, 3, no, 4 o'clock tomorrow.
        Output: The meeting is at 4 o'clock tomorrow.
        """
    }
}
