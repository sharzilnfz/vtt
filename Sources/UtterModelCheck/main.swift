import FluidAudio
import Foundation
import UtterCore

@main
struct ModelCheck {
    static func main() async throws {
        let store = STTModelStore()
        let provider = FluidAudioProvider(selection: store.selection)
        print("Downloading and loading \(store.selection.displayName) into \(AsrModels.defaultCacheDirectory(for: .v2).path)")
        let manager = try await provider.loadIfNeeded()
        print("Parakeet V2 loaded")
        if let path = CommandLine.arguments.dropFirst().first {
            let layerCount = await manager.decoderLayerCount
            var decoderState = try TdtDecoderState(decoderLayers: layerCount)
            let result = try await manager.transcribe(URL(fileURLWithPath: path), decoderState: &decoderState)
            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "UtterModelCheck", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Speech fixture produced an empty transcript"])
            }
            print(result.text)
        }
    }
}
