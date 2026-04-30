import Foundation

@MainActor
class ScribeManager: ObservableObject {
    @Published var isTranscribing = false
    @Published private(set) var statusText: String = "未設定"

    private let settings: SettingsManager
    private let session: URLSession

    private nonisolated static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    private nonisolated static let modelID = "scribe_v2"
    private nonisolated static let requestTimeout: TimeInterval = 60

    init(settings: SettingsManager, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
        refreshStatusText()
    }

    func refreshStatusText() {
        statusText = settings.trimmedElevenLabsApiKey.isEmpty ? "APIキー未設定" : "準備完了"
    }

    /// 音声ファイルを ElevenLabs Scribe v2 (Batch API) で文字起こしする。
    ///
    /// - Parameters:
    ///   - audioURL: ローカルに書き出された音声ファイルの URL（recording.wav 想定）。
    ///   - language: "ja" / "en" / "auto"。"auto" のときは language_code を送らず Scribe 側の自動検出に委ねる。
    /// - Returns: 認識結果テキスト。失敗時は空文字列（statusText にエラー文を反映）。
    func transcribe(audioURL: URL, language: String = "ja") async -> String {
        let apiKey = settings.trimmedElevenLabsApiKey
        guard !apiKey.isEmpty else {
            statusText = "APIキー未設定"
            return ""
        }

        isTranscribing = true
        defer { isTranscribing = false }

        statusText = "送信中..."

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            statusText = "失敗: 録音ファイル読込エラー"
            return ""
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            audioFilename: audioURL.lastPathComponent,
            language: language
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.requestTimeout

        do {
            let (data, response) = try await session.upload(for: request, from: body)
            guard let http = response as? HTTPURLResponse else {
                statusText = "失敗: レスポンス取得失敗"
                return ""
            }
            guard (200..<300).contains(http.statusCode) else {
                statusText = "失敗: HTTP \(http.statusCode)"
                return ""
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                statusText = "失敗: レスポンス形式不正"
                return ""
            }
            statusText = "準備完了"
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            statusText = "失敗: \(error.localizedDescription)"
            return ""
        }
    }

    /// multipart/form-data 本体を組み立てる。`@MainActor` 内で使うが副作用なしの純粋関数なので
    /// `nonisolated static` で隔離解除し、テスト（XCTestCase の nonisolated context）から
    /// sync で呼べるようにする（AudioRecorder.makeTapHandler と同パターン）。
    nonisolated static func makeMultipartBody(
        boundary: String,
        audioData: Data,
        audioFilename: String,
        language: String
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("\(modelID)\(crlf)".data(using: .utf8)!)

        if language != "auto" {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language_code\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append("\(language)\(crlf)".data(using: .utf8)!)
        }

        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFilename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(audioData)
        body.append("\(crlf)".data(using: .utf8)!)

        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)

        return body
    }
}
