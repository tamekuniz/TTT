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
}
