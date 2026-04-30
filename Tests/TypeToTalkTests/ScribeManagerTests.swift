import XCTest
@testable import TypeToTalk

final class ScribeManagerTests: XCTestCase {
    @MainActor
    func testTranscribeReturnsEmptyStringWhenApiKeyIsEmpty() async throws {
        let settings = SettingsManager()
        settings.elevenLabsApiKey = ""
        let session = makeMockSession { _ in
            XCTFail("session should not be called when api key is empty")
            return (Data(), HTTPURLResponse())
        }
        let manager = ScribeManager(settings: settings, session: session)

        let audioURL = try writeDummyAudio()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = await manager.transcribe(audioURL: audioURL, language: "ja")
        XCTAssertEqual(result, "")
        XCTAssertEqual(manager.statusText, "APIキー未設定")
    }

    @MainActor
    func testTranscribeReturnsTextOnValidJSONResponse() async throws {
        let settings = SettingsManager()
        settings.elevenLabsApiKey = "test-key"
        let responseJSON = #"{"text": "こんにちは世界"}"#
        let session = makeMockSession { request in
            let body = try Self.unwrapBody(request: request)
            XCTAssertTrue(body.contains("model_id"))
            XCTAssertTrue(body.contains("scribe_v2"))
            XCTAssertTrue(body.contains("language_code"))
            XCTAssertTrue(body.contains("ja"))
            XCTAssertTrue(body.contains("filename="))
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-key")
            return (
                responseJSON.data(using: .utf8)!,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let manager = ScribeManager(settings: settings, session: session)

        let audioURL = try writeDummyAudio()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = await manager.transcribe(audioURL: audioURL, language: "ja")
        XCTAssertEqual(result, "こんにちは世界")
    }

    @MainActor
    func testTranscribeReturnsEmptyStringWhenTextFieldMissing() async throws {
        let settings = SettingsManager()
        settings.elevenLabsApiKey = "test-key"
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return ("{}".data(using: .utf8)!, response)
        }
        let manager = ScribeManager(settings: settings, session: session)

        let audioURL = try writeDummyAudio()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = await manager.transcribe(audioURL: audioURL, language: "ja")
        XCTAssertEqual(result, "")
        XCTAssertEqual(manager.statusText, "失敗: レスポンス形式不正")
    }

    @MainActor
    func testTranscribeReturnsEmptyStringOnHTTP401() async throws {
        let settings = SettingsManager()
        settings.elevenLabsApiKey = "wrong-key"
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let manager = ScribeManager(settings: settings, session: session)

        let audioURL = try writeDummyAudio()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = await manager.transcribe(audioURL: audioURL, language: "ja")
        XCTAssertEqual(result, "")
        XCTAssertEqual(manager.statusText, "失敗: HTTP 401")
    }

    func testMakeMultipartBodyContainsAllRequiredFields() {
        let audioData = "fake-audio-bytes".data(using: .utf8)!
        let body = ScribeManager.makeMultipartBody(
            boundary: "TestBoundary",
            audioData: audioData,
            audioFilename: "recording.wav",
            language: "ja"
        )
        let bodyString = String(data: body, encoding: .utf8) ?? ""

        XCTAssertTrue(bodyString.contains("--TestBoundary"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"model_id\""))
        XCTAssertTrue(bodyString.contains("scribe_v2"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"language_code\""))
        XCTAssertTrue(bodyString.contains("ja"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/wav"))
        XCTAssertTrue(bodyString.contains("--TestBoundary--"))
        XCTAssertTrue(bodyString.contains("fake-audio-bytes"))
    }

    func testMakeMultipartBodyOmitsLanguageCodeWhenAuto() {
        let audioData = Data([0x00, 0x01])
        let body = ScribeManager.makeMultipartBody(
            boundary: "TestBoundary",
            audioData: audioData,
            audioFilename: "recording.wav",
            language: "auto"
        )
        let bodyString = String(data: body, encoding: .utf8) ?? ""

        XCTAssertFalse(bodyString.contains("name=\"language_code\""))
        XCTAssertTrue(bodyString.contains("scribe_v2"))
    }

    private func writeDummyAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-test-\(UUID().uuidString).wav")
        try "dummy".data(using: .utf8)!.write(to: url)
        return url
    }

    private func makeMockSession(handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = handler
        return URLSession(configuration: config)
    }

    private static func unwrapBody(request: URLRequest) throws -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
}

/// URLSession に挿し込んでリクエストを横取りするモック。
/// テスト毎に `MockURLProtocol.handler` を設定して使う。
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
