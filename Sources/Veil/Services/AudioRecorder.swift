import AVFoundation

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    var outputURL: URL?
    var onDone: ((URL?) -> Void)?

    func start() {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollama_audio_\(Int(Date().timeIntervalSince1970)).wav")
        outputURL = tmpURL
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        inputNode = engine.inputNode
        guard let input = inputNode else { return }
        let fmt = input.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do { audioFile = try AVAudioFile(forWriting: tmpURL, settings: settings) }
        catch { print("[audio] \(error)"); return }
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            if let c = self.convert(buffer: buffer, to: file.processingFormat) { try? file.write(from: c) }
            else { try? file.write(from: buffer) }
        }
        do { try engine.start() } catch { print("[audio] engine: \(error)") }
    }

    func stop() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil; audioFile = nil
        onDone?(outputURL)
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != format,
              let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio    = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?; var done = false
        converter.convert(to: out, error: &error) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData; done = true; return buffer
        }
        return error == nil ? out : nil
    }
}
