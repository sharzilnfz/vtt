import Accelerate
import AVFoundation
import Foundation

public protocol AudioCaptureServiceProtocol: Sendable {
    func startCapture(onLevelUpdate: (@Sendable (Float) -> Void)?) throws
    func stopCapture() -> [Int16]
    var isCapturing: Bool { get }
}

public final class AudioCaptureService: @unchecked Sendable, AudioCaptureServiceProtocol {
    private let audioEngine = AVAudioEngine()
    private let lock = NSLock()
    private let lifecycleLock = NSLock()
    private var recordedSamples: [Int16] = []
    private var _isCapturing = false
    private var lastLevelTime: DispatchTime = .now()
    private var lastEmittedLevel: Float = 0.0

    public init() {}

    public var isCapturing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCapturing
    }

    public func startCapture(onLevelUpdate: (@Sendable (Float) -> Void)? = nil) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard !isCapturing else { return }
        lock.lock()
        recordedSamples.removeAll()
        lock.unlock()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "VTTAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create target audio format"])
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "VTTAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate))
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            var allConsumed = false
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if !allConsumed {
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            guard error == nil, let channelData = convertedBuffer.int16ChannelData else { return }
            let frameLength = Int(convertedBuffer.frameLength)
            guard frameLength > 0 else { return }

            var chunk = [Int16](repeating: 0, count: frameLength)
            chunk.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress?.update(from: channelData[0], count: frameLength)
            }

            let level: Float? = (onLevelUpdate != nil) ? Self.calculateNormalizedLevel(from: chunk) : nil

            self.lock.lock()
            let acceptingSamples = self._isCapturing
            if acceptingSamples {
                self.recordedSamples.append(contentsOf: chunk)
            }
            var shouldEmitLevel = false
            var levelToEmit: Float = 0.0
            if acceptingSamples, let level, onLevelUpdate != nil {
                let now = DispatchTime.now()
                let elapsedNanos = now.uptimeNanoseconds - self.lastLevelTime.uptimeNanoseconds
                let delta = abs(level - self.lastEmittedLevel)
                if elapsedNanos >= 60_000_000 || delta > 0.05 {
                    self.lastLevelTime = now
                    self.lastEmittedLevel = level
                    shouldEmitLevel = true
                    levelToEmit = level
                }
            }
            self.lock.unlock()

            if shouldEmitLevel, let onLevelUpdate {
                onLevelUpdate(levelToEmit)
            }
        }

        lock.lock()
        _isCapturing = true
        lock.unlock()
        do {
            try audioEngine.start()
        } catch {
            lock.lock()
            _isCapturing = false
            lock.unlock()
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            lock.lock()
            recordedSamples.removeAll()
            lock.unlock()
            throw error
        }
    }

    public func stopCapture() -> [Int16] {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        lock.lock()
        guard _isCapturing else {
            lock.unlock()
            return []
        }
        _isCapturing = false
        lock.unlock()

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        lock.lock()
        let samples = recordedSamples
        recordedSamples.removeAll()
        lock.unlock()
        return samples
    }

    public static func calculateNormalizedLevel(from samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        var rms: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            var floatBuf = [Float](repeating: 0, count: min(samples.count, 1024))
            let stride = max(1, samples.count / 1024)
            var count = 0
            var idx = 0
            while idx < samples.count && count < 1024 {
                floatBuf[count] = Float(base[idx]) / 32768.0
                count += 1
                idx += stride
            }
            vDSP_rmsqv(floatBuf, 1, &rms, vDSP_Length(count))
        }

        let db = 20 * log10(max(rms, 0.0001))
        let minDb: Float = -50.0
        let normalized = (db - minDb) / (-minDb)
        return max(0.0, min(1.0, normalized))
    }
}
