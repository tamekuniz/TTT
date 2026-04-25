import Foundation
import Hub
import MLXLLM
import MLXLMCommon
import Tokenizers

enum BonsaiLoadState: Equatable {
    case idle
    case loading
    case loaded(modelID: String)
    case failed(message: String)
}

@MainActor
final class BonsaiManager: ObservableObject {
    @Published private(set) var isModelLoaded = false
    @Published private(set) var loadedModelID: String?
    @Published private(set) var statusMessage = "未読込"
    @Published private(set) var isLoadingModel = false
    @Published private(set) var loadState: BonsaiLoadState = .idle
    
    private var modelContainer: ModelContainer?
    private let downloader: any Downloader
    private let tokenizerLoader: any TokenizerLoader
    private let modelsBaseDirectory: URL

    init() {
        let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typetotalk/models")
        self.modelsBaseDirectory = baseDirectory
        self.downloader = HuggingFaceHubDownloader(downloadBase: baseDirectory)
        self.tokenizerLoader = HuggingFaceTokenizerLoader()
    }
    
    func processText(_ text: String, prompt: String, modelID: String) async -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return text }
        guard let container = loadedContainer(for: modelID) else {
            statusMessage = "モデルを読み込んでください"
            return text
        }
        
        do {
            statusMessage = "準備完了"
            let session = ChatSession(
                container,
                instructions: prompt,
                generateParameters: .init(
                    maxTokens: 384,
                    temperature: 0,
                    topP: 1,
                    topK: 0
                )
            )
            let response = try await session.respond(to: trimmedText)
            let formatted = response.trimmingCharacters(in: .whitespacesAndNewlines)
            statusMessage = "準備完了"
            return formatted.isEmpty ? text : formatted
        } catch {
            statusMessage = "エラー: \(error.localizedDescription)"
            print("Bonsai error: \(error)")
            return text
        }
    }
    
    var needsExplicitLoad: Bool {
        loadedModelID != currentSelectedModelID
    }

    var canAutoLoad: Bool {
        !currentSelectedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var currentSelectedModelID: String = ""
    
    var loadedModelDisplayName: String {
        loadedModelID ?? "未読込"
    }
    
    func configureSelectedModel(_ modelID: String) {
        currentSelectedModelID = modelID
        switch loadState {
        case .idle:
            statusMessage = "未読込"
        case .loading:
            statusMessage = "読込中"
        case .loaded:
            statusMessage = loadedModelID == modelID ? "準備完了" : "未読込"
        case .failed:
            break
        }
    }
    
    func loadSelectedModel(modelID: String) async {
        currentSelectedModelID = modelID
        do {
            _ = try await loadModel(modelID: modelID)
        } catch {
            let message = error.localizedDescription
            loadState = .failed(message: message)
            statusMessage = "失敗: \(message)"
        }
    }

    func ensureSelectedModelLoaded(modelID: String) async {
        currentSelectedModelID = modelID
        guard canAutoLoad else { return }
        // 自動ロードはローカルにモデルが既にダウンロードされている場合のみ。
        // 未ダウンロードなら勝手にネットへ取りに行かず、状態は .idle のままサイレントに return。
        // 明示的な「再読込」は loadSelectedModel(modelID:) 経由で行うこと。
        guard isLocalModelAvailable(modelID: modelID) else { return }
        do {
            _ = try await loadModel(modelID: modelID)
        } catch {
            let message = error.localizedDescription
            loadState = .failed(message: message)
            statusMessage = "失敗: \(message)"
        }
    }

    /// `~/.typetotalk/models/<modelID>/` にモデル本体が既にダウンロードされ、中身が空でないかを判定する。
    ///
    /// `HuggingFaceHubDownloader` (= `HubApi.snapshot`) は `<downloadBase>/<modelID>/` 配下に展開するため、
    /// ここで参照する `modelsBaseDirectory` は init で `downloader` に渡したものと同一でなければならない。
    private func isLocalModelAvailable(modelID: String) -> Bool {
        let modelDir = modelsBaseDirectory.appendingPathComponent(modelID)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        // 中途半端に作られた空ディレクトリへの防御
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path)) ?? []
        return !contents.isEmpty
    }
    
    func loadedContainer(for modelID: String) -> ModelContainer? {
        guard loadedModelID == modelID else { return nil }
        return modelContainer
    }
    
    private func loadModel(modelID: String) async throws -> ModelContainer {
        if let modelContainer, loadedModelID == modelID {
            return modelContainer
        }
        
        isLoadingModel = true
        loadState = .loading
        statusMessage = "読込中"
        defer { isLoadingModel = false }
        
        do {
            let container = try await loadModelContainer(
                from: downloader,
                using: tokenizerLoader,
                configuration: .init(id: modelID),
                useLatest: false
            ) { [weak self] progress in
                Task { @MainActor in
                    let percent = Int(progress.fractionCompleted * 100)
                    self?.statusMessage = percent > 0 ? "モデル取得中 \(percent)%" : "モデル取得中"
                }
            }
            
            self.modelContainer = container
            self.loadedModelID = modelID
            self.isModelLoaded = true
            self.loadState = .loaded(modelID: modelID)
            self.statusMessage = "準備完了"
            return container
        } catch {
            self.modelContainer = nil
            self.loadedModelID = nil
            self.isModelLoaded = false
            throw error
        }
    }
}

private struct HuggingFaceHubDownloader: Downloader {
    private let hubApi: HubApi
    
    init(downloadBase: URL) {
        self.hubApi = HubApi(downloadBase: downloadBase)
    }
    
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let revision = revision ?? "main"
        return try await hubApi.snapshot(
            from: id,
            revision: revision,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

private struct HuggingFaceTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return HuggingFaceTokenizerBridge(tokenizer)
    }
}

private struct HuggingFaceTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer
    
    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }
    
    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }
    
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }
    
    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }
    
    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }
    
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
    
    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
