import Foundation
import AVFoundation

protocol AudioBufferWriting: Sendable {
    func write(_ buffer: AVAudioPCMBuffer)
}

private final class AudioFileWriter: @unchecked Sendable {
    private let audioFile: AVAudioFile

    init(audioFile: AVAudioFile) {
        self.audioFile = audioFile
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        try? audioFile.write(from: buffer)
    }
}

extension AudioFileWriter: AudioBufferWriting {}

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    enum RecordingError: LocalizedError {
        case microphonePermissionDenied
        case noInputDeviceAvailable
        case invalidInputFormat

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "マイクへのアクセスが許可されていません"
            case .noInputDeviceAvailable:
                return "利用可能な入力デバイスが見つかりません"
            case .invalidInputFormat:
                return "録音フォーマットを初期化できませんでした"
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    
    @Published var isRecording = false
    
    func startRecording() async throws -> URL {
        guard await requestMicrophoneAccessIfNeeded() else {
            throw RecordingError.microphonePermissionDenied
        }

        stopRecording()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            throw recordingFormat.channelCount == 0
                ? RecordingError.noInputDeviceAvailable
                : RecordingError.invalidInputFormat
        }
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        
        self.recordingURL = url
        let audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        self.audioFile = audioFile
        let writer = AudioFileWriter(audioFile: audioFile)
        
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat,
            block: Self.makeTapHandler(writer: writer)
        )
        
        audioEngine = engine
        try engine.start()
        isRecording = true
        return url
    }
    
    func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false
        audioEngine = nil
        audioFile = nil
    }

    private func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    nonisolated static func makeTapHandler(
        writer: some AudioBufferWriting
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            writer.write(buffer)
        }
    }
}
