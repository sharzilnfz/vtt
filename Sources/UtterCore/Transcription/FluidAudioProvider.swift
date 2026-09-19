import Accelerate
import Foundation
import FluidAudio

public actor FluidAudioProvider: TranscriptionServiceProtocol {
    private static let upstreamV2Repo = "FluidInference/parakeet-tdt-0.6b-v2-coreml"

    private var selection: STTModelSelection
    private var asrManager: AsrManager?
    private var loadedKey: String?

    public init(selection: STTModelSelection = .builtIn(.v2)) {
        self.selection = selection
    }

    public func updateSelection(_ selection: STTModelSelection) {
        if selection != self.selection {
            self.selection = selection
            asrManager = nil
            loadedKey = nil
        }
    }

    public var currentSelection: STTModelSelection {
        selection
    }

    private static func cacheKey(for selection: STTModelSelection) -> String {
        switch selection {
        case .builtIn: return "builtin:v2"
        case .custom(let custom): return "custom:\(custom.repo)"
        }
    }

    public func loadIfNeeded(progress: ProgressHandler? = nil) async throws -> AsrManager {
        let key = Self.cacheKey(for: selection)
        if let manager = asrManager, loadedKey == key {
            return manager
        }

        let previousOverrides = ModelRegistry.repoOverrides
        if let customRepo = selection.customRepo {
            var overrides = previousOverrides
            overrides[Self.upstreamV2Repo] = customRepo
            ModelRegistry.repoOverrides = overrides
        } else {
            ModelRegistry.repoOverrides = [:]
        }
        defer {
            if selection.customRepo == nil {
                ModelRegistry.repoOverrides = previousOverrides
            }
        }

        let models = try await AsrModels.downloadAndLoad(version: .v2, progressHandler: progress)
        let manager = AsrManager(models: models)
        self.asrManager = manager
        self.loadedKey = key
        return manager
    }

    public func transcribe(samples: [Int16]) async throws -> TranscriptionResult {
        let manager = try await loadIfNeeded()

        let floatSamples = Self.convertToFloat(samples)
        let duration = Double(samples.count) / 16000.0

        let layerCount = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: layerCount)

        let result = try await manager.transcribe(floatSamples, decoderState: &decoderState)
        return TranscriptionResult(
            text: result.text,
            durationSeconds: duration,
            confidence: result.confidence
        )
    }

    public func unload() {
        asrManager = nil
        loadedKey = nil
        if selection.customRepo != nil {
            ModelRegistry.repoOverrides = [:]
        }
    }

    public nonisolated static func removeLegacyCaches() {
        let versions: [AsrModelVersion] = [.tdtCtc110m, .v3, .tdtJa]
        for version in versions {
            let dir = AsrModels.defaultCacheDirectory(for: version)
            if FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    nonisolated static func convertToFloat(_ samples: [Int16]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var output = [Float](repeating: 0, count: samples.count)
        samples.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                guard let srcBase = src.baseAddress, let dstBase = dst.baseAddress else { return }
                vDSP_vflt16(srcBase, 1, dstBase, 1, vDSP_Length(samples.count))
                var divisor: Float = 32768.0
                vDSP_vsdiv(dstBase, 1, &divisor, dstBase, 1, vDSP_Length(samples.count))
            }
        }
        return output
    }
}
