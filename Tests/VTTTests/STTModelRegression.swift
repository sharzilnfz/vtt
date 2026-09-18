import Foundation
@testable import VTTCore

private struct STTRegressionFailure: Error {
    let message: String
}

@MainActor
func runSTTModelRegressions() throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw STTRegressionFailure(message: message) }
    }

    try check(try STTModelStore.normalizeRepo("https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml") == "FluidInference/parakeet-tdt-0.6b-v2-coreml", "Full HTTPS link must parse")
    try check(try STTModelStore.normalizeRepo("huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/tree/main") == "FluidInference/parakeet-tdt-0.6b-v2-coreml", "Tree suffix must strip")
    try check(try STTModelStore.normalizeRepo("MyOrg/my-model") == "MyOrg/my-model", "Bare org/repo must pass")
    try check(try STTModelStore.normalizeRepo("  hf://MyOrg/my-model  ") == "MyOrg/my-model", "hf:// must parse with whitespace trim")
    try check(try STTModelStore.normalizeRepo("https://huggingface.co/org/repo?query=1") == "org/repo", "Query must strip")
    do {
        _ = try STTModelStore.normalizeRepo("https://example.com/org/repo")
        throw STTRegressionFailure(message: "Non-HF host must fail")
    } catch STTModelLinkError.unsupportedHost { } catch { throw STTRegressionFailure(message: "Wrong error for non-HF host") }
    do {
        _ = try STTModelStore.normalizeRepo("not-a-repo")
        throw STTRegressionFailure(message: "Single path must fail")
    } catch STTModelLinkError.invalidFormat { } catch { throw STTRegressionFailure(message: "Wrong error for bad format") }
    do {
        _ = try STTModelStore.normalizeRepo("   ")
        throw STTRegressionFailure(message: "Empty must fail")
    } catch STTModelLinkError.empty { } catch { throw STTRegressionFailure(message: "Wrong error for empty") }

    let suite = "VTT.stt.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = STTModelStore(defaults: defaults)
    try check(store.selection == .builtIn(.v2), "Default must be v2")
    store.selectBuiltIn()
    try check(store.selection.displayName == "Parakeet 0.6B v2", "Display name must match")
    let restored = STTModelStore(defaults: defaults)
    try check(restored.selection == .builtIn(.v2), "Selection must persist")
    try restored.selectCustom(repo: "https://huggingface.co/MyOrg/my-model")
    try check(restored.selection.customRepo == "MyOrg/my-model", "Custom repo must normalize")
    try check(restored.selection.effectiveBuiltIn == .v2, "Custom base must be v2")
    let restored2 = STTModelStore(defaults: defaults)
    try check(restored2.selection.customRepo == "MyOrg/my-model", "Custom must persist")

    defaults.set("{\"builtIn\":{\"_0\":\"tdtCtc110m\"}}".data(using: .utf8)!, forKey: "vtt.stt.model.selection")
    let migrated = STTModelStore(defaults: defaults)
    try check(migrated.selection == .builtIn(.v2), "Legacy 110M stored selection must migrate to v2")

    let floatResult = FluidAudioProvider.convertToFloat([0, 16384, -16384, 32767, -32768])
    try check(floatResult.count == 5, "Float conversion must preserve count")
    try check(abs(floatResult[0] - 0.0) < 0.001, "Zero must map to zero")
    try check(abs(floatResult[1] - 0.5) < 0.001, "16384 must map to 0.5")
    try check(abs(floatResult[3] - 0.9999) < 0.002, "Max must map near 1.0")
    try check(FluidAudioProvider.convertToFloat([]).isEmpty, "Empty must stay empty")

    let levelSilence = AudioCaptureService.calculateNormalizedLevel(from: [Int16](repeating: 0, count: 512))
    let levelLoud = AudioCaptureService.calculateNormalizedLevel(from: [Int16](repeating: 20000, count: 512))
    try check(levelSilence < 0.05, "Silence must be near zero")
    try check(levelLoud > 0.7, "Loud must be high")
    try check(levelSilence <= levelLoud, "Level must be monotonic")
}

@MainActor
func runSTTBannerRegressions() throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw STTRegressionFailure(message: message) }
    }
    let buffer = SafetyBuffer()
    let settings = RefinementSettingsStore(defaults: UserDefaults(suiteName: "VTT.stt.banner.\(UUID().uuidString)")!)
    let state = DashboardState(safetyBuffer: buffer, settingsStore: settings)
    state.showTransientBanner("first", type: .info, duration: 5.0)
    state.showTransientBanner("second", type: .success, duration: 5.0)
    try check(state.bannerMessage == "second", "Second banner must replace first without leak")
    try check(state.bannerType == .success, "Banner type must update")
}
