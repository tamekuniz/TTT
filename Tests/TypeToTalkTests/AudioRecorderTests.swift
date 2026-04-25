import XCTest
@preconcurrency import AVFoundation
@testable import TypeToTalk

final class AudioRecorderTests: XCTestCase {
    @MainActor
    func testTapHandlerWritesBufferOffMainThread() async {
        let writer = CountingBufferWriter()
        let handler = AudioRecorder.makeTapHandler(writer: writer)
        let buffer = makeBuffer()
        let time = AVAudioTime(sampleTime: 0, atRate: 16_000)
        let expectation = expectation(description: "tap handler finished")

        DispatchQueue.global(qos: .userInitiated).async {
            handler(buffer, time)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(writer.writeCount, 1)
    }

    func testTapHandlerCanBeInvokedRepeatedly() {
        let writer = CountingBufferWriter()
        let handler = AudioRecorder.makeTapHandler(writer: writer)
        let time = AVAudioTime(sampleTime: 0, atRate: 16_000)

        for _ in 0..<3 {
            handler(makeBuffer(), time)
        }

        XCTAssertEqual(writer.writeCount, 3)
    }

    private func makeBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        buffer.frameLength = 16
        return buffer
    }

    /// `startRecording()` が返す URL が一時ディレクトリ配下の `recording.wav` であることを
    /// 検証する。マイク権限が許可された環境（実機実行）でのみ URL が返り、それ以外は
    /// `RecordingError.microphonePermissionDenied` が throw される。
    ///
    /// CI / sandbox / 権限未許可環境では throw 経路を検証する。実 URL の一致検証は
    /// 権限が許可されている環境でのみ意味を持つため、その場合のみ assert する。
    /// 実機での録音動作確認は別途 manual test に委ねる。
    @MainActor
    func testStartRecordingReturnsExpectedURLOrThrowsWhenPermissionDenied() async {
        let recorder = AudioRecorder()
        let expectedURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")

        do {
            let url = try await recorder.startRecording()
            // 権限が許可されている環境のみここに到達する
            XCTAssertEqual(url, expectedURL)
            recorder.stopRecording()
        } catch let error as AudioRecorder.RecordingError {
            // 権限拒否 / 入力デバイス無し / フォーマット不正のいずれかであれば想定内
            switch error {
            case .microphonePermissionDenied,
                 .noInputDeviceAvailable,
                 .invalidInputFormat:
                break
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class CountingBufferWriter: @unchecked Sendable, AudioBufferWriting {
    private let lock = NSLock()
    private var writes = 0

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        writes += 1
        lock.unlock()
    }
}
