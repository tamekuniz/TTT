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
    @Published var whisperKit: WhisperKit? {
        didSet { refreshStatusText() }
    }
    @Published var isTranscribing = false
    @Published var lastTranscription: String = ""
    @Published var isLoadingModel = false
    @Published private(set) var loadState: WhisperLoadState = .idle {
        didSet { refreshStatusText() }
    }
    @Published private(set) var loadingStatusText = "未読込" {
        didSet { refreshStatusText() }
    }
    @Published private(set) var statusText: String = "未読込"

    private let settings: SettingsManager
    private var loadedModelID: String? {
        didSet { refreshStatusText() }
    }

    init(settings: SettingsManager) {
        self.settings = settings
        refreshStatusText()
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
    
    private func refreshStatusText() {
        switch loadState {
        case .idle:
            statusText = needsExplicitLoad ? "未読込" : "準備完了"
        case .loading:
            statusText = loadingStatusText
        case .loaded:
            statusText = needsExplicitLoad ? "未読込" : "準備完了"
        case let .failed(message):
            statusText = "失敗: \(message)"
        }
    }
    
    func loadSelectedModel() async {
        await setupWhisper(forceReload: true)
    }

    func ensureSelectedModelLoaded() async {
        guard canAutoLoad else { return }
        // 自動ロードはローカルにモデルが既にダウンロードされている場合のみ。
        // 未ダウンロードなら勝手にネットへ取りに行かず、状態は .idle のままサイレントに return。
        // 明示的な「再読込」は loadSelectedModel() 経由で行うこと。
        guard isLocalModelAvailable(variant: selectedModelID) else { return }
        await setupWhisper(forceReload: false)
    }

    func unloadModel() {
        whisperKit = nil
        loadedModelID = nil
        loadState = .idle
    }

    /// WhisperKit が利用するローカルキャッシュ（`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/`）
    /// に該当 variant のモデルディレクトリが存在し、中身が空でないかを判定する。
    ///
    /// - Note: `HubApi(downloadBase: nil)` のデフォルト挙動 (`Documents/huggingface`) と
    ///         `localRepoLocation`（`<base>/<repoType>/<repoID>`）の組み合わせに合わせている。
    private func isLocalModelAvailable(variant: String) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelDir = documents
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(variant)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        // 中途半端に作られた空ディレクトリへの防御
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path)) ?? []
        return !contents.isEmpty
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
    
    /// 音声ファイルを文字起こしする。
    ///
    /// - Parameters:
    ///   - audioURL: 入力音声ファイルの URL。
    ///   - language: "ja" / "en" / "auto"。"auto" は WhisperKit の言語自動検出を有効化し、
    ///               それ以外は DecodingOptions.language に明示する。デフォルトは "ja"（既存挙動互換）。
    /// - Returns: 認識結果テキスト。失敗時は空文字列。
    func transcribe(audioURL: URL, language: String = "ja") async -> String {
        guard let whisperKit = whisperKit else {
            return ""
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let decodeOptions: DecodingOptions
        if language == "auto" {
            // language 未指定 + detectLanguage 明示で WhisperKit 内部の自動検出に委ねる
            decodeOptions = DecodingOptions(detectLanguage: true)
        } else {
            decodeOptions = DecodingOptions(language: language)
        }

        do {
            // WhisperKit 0.18.0: transcribe(audioPath:decodeOptions:callback:) async throws -> [TranscriptionResult]
            let results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: decodeOptions
            )
            let combinedText = results.compactMap { $0.text }.joined(separator: " ")
            lastTranscription = combinedText
            return combinedText
        } catch {
            print("Transcription failed: \(error)")
            return ""
        }
    }
}
