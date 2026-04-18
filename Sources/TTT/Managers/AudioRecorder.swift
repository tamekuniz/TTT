import Foundation
import AVFoundation

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    
    @Published var isRecording = false
    
    func startRecording() throws -> URL {
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine!.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        
        self.recordingURL = url
        audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, time) in
            try? self.audioFile?.write(from: buffer)
        }
        
        try audioEngine!.start()
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
}
