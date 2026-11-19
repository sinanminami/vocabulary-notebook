import AVFoundation
import VocabularyCore

@MainActor
final class WordPronouncer {
    private let synthesizer = AVSpeechSynthesizer()
    private var renderJob: SpeechRenderJob?
    private var player: AVAudioPlayer?
    private var activeRequestID = UUID()
    private var activeAudioURL: URL?

    func speak(term: String, languageCode: LanguageCode) {
        let text = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        stop()

        let requestID = UUID()
        activeRequestID = requestID
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("word-pronunciation-\(requestID.uuidString)")
            .appendingPathExtension("caf")

        let job = SpeechRenderJob(outputURL: audioURL) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.finishRendering(result, requestID: requestID)
            }
        }
        renderJob = job

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage(for: languageCode))
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.write(utterance) { buffer in
            job.consume(buffer)
        }
    }

    func stop() {
        activeRequestID = UUID()
        synthesizer.stopSpeaking(at: .immediate)
        renderJob?.cancel()
        renderJob = nil
        player?.stop()
        player = nil
        removeActiveAudioFile()
    }

    private func finishRendering(
        _ result: Result<URL, any Error>,
        requestID: UUID
    ) {
        renderJob = nil
        guard requestID == activeRequestID else {
            if case let .success(url) = result {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        guard case let .success(url) = result else { return }
        do {
            let preparedPlayer = try AVAudioPlayer(contentsOf: url)
            preparedPlayer.volume = 1.0
            preparedPlayer.prepareToPlay()
            activeAudioURL = url
            player = preparedPlayer
            preparedPlayer.play()
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeActiveAudioFile() {
        guard let activeAudioURL else { return }
        try? FileManager.default.removeItem(at: activeAudioURL)
        self.activeAudioURL = nil
    }

    private func voiceLanguage(for languageCode: LanguageCode) -> String {
        switch languageCode {
        case .english:
            "en-US"
        case .japanese:
            "ja-JP"
        default:
            languageCode == .undetermined ? "en-US" : languageCode.rawValue
        }
    }
}

private final class SpeechRenderJob: @unchecked Sendable {
    private static let warmupDuration: TimeInterval = 0.35
    private static let tailDuration: TimeInterval = 0.25
    private static let inaudibleWarmupAmplitude: Float = 0.00025
    private static let warmupFrequency: Double = 120

    private let outputURL: URL
    private let completion: @Sendable (Result<URL, any Error>) -> Void
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    private var isCancelled = false
    private var isFinished = false

    init(
        outputURL: URL,
        completion: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) {
        self.outputURL = outputURL
        self.completion = completion
    }

    func consume(_ buffer: AVAudioBuffer) {
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

        lock.lock()
        if isCancelled || isFinished {
            lock.unlock()
            return
        }

        if pcmBuffer.frameLength == 0 {
            do {
                if let audioFile, let audioFormat {
                    try audioFile.write(from: makePaddingBuffer(
                        format: audioFormat,
                        duration: Self.tailDuration,
                        includesWarmupSignal: false
                    ))
                }
                isFinished = true
                audioFile = nil
                audioFormat = nil
                lock.unlock()
                completion(.success(outputURL))
            } catch {
                isFinished = true
                audioFile = nil
                audioFormat = nil
                lock.unlock()
                completion(.failure(error))
            }
            return
        }

        do {
            if audioFile == nil {
                let file = try AVAudioFile(
                    forWriting: outputURL,
                    settings: pcmBuffer.format.settings
                )
                try file.write(from: makePaddingBuffer(
                    format: pcmBuffer.format,
                    duration: Self.warmupDuration,
                    includesWarmupSignal: true
                ))
                audioFile = file
                audioFormat = pcmBuffer.format
            }
            try audioFile?.write(from: pcmBuffer)
            lock.unlock()
        } catch {
            isFinished = true
            audioFile = nil
            lock.unlock()
            completion(.failure(error))
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        audioFile = nil
        audioFormat = nil
        lock.unlock()
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func makePaddingBuffer(
        format: AVAudioFormat,
        duration: TimeInterval,
        includesWarmupSignal: Bool
    ) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(
            (format.sampleRate * duration).rounded(.up)
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw SpeechRenderError.unableToCreateWarmupBuffer
        }
        buffer.frameLength = frameCount

        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for audioBuffer in buffers {
            if let data = audioBuffer.mData {
                memset(data, 0, Int(audioBuffer.mDataByteSize))
            }
        }

        if includesWarmupSignal, let channels = buffer.floatChannelData {
            let channelCount = Int(format.channelCount)
            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / format.sampleRate
                let sample = Self.inaudibleWarmupAmplitude * Float(
                    sin(2 * Double.pi * Self.warmupFrequency * time)
                )
                for channel in 0..<channelCount {
                    channels[channel][frame] = sample
                }
            }
        }

        return buffer
    }
}

private enum SpeechRenderError: Error {
    case unableToCreateWarmupBuffer
}
