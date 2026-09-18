# VTT efficiency research and foundation recommendation

Research by Union Alpha. September 17, 2026.

This document records the stack research, foundation comparison, local environment checks, and remaining verification work. It does not replace `CONTEXT.md`, `FOUNDATIONS.md`, `EFFICIENCY.md`, or either existing review.

## Goal

Build a minimal speech-to-text application with low runtime overhead on the user's Mac. Prioritize idle resource use, memory pressure, and energy per dictation over feature richness. SwiftUI is not a fixed requirement.

The earlier recommendation to reduce FluidVoice prioritized reuse of a complete application. With machine efficiency as the primary goal, the recommendation changes to a smaller native foundation and explicit inference-lifecycle management.

## Recommendation

**Use a small native Swift/AppKit application with one on-device transcription engine. Start by validating a reduced MiniWhisper fork using upstream FluidAudio.**

Use a lazily created settings UI, bounded audio buffers, and adaptive model retention. Avoid a permanently running webview, continuous transcription, and a resident local LLM server.

SwiftUI is optional. Rust is viable, but Rust alone does not make a dictation application more efficient than Swift. The inference backend, model residency, and background activity will usually matter more.

Benchmark Parakeet TDT-CTC 110M against Parakeet 0.6B v2 before selecting the shipped model. Compare the winner with a native C++/Metal backend and Apple Speech before claiming market-leading efficiency.

**This is an architectural recommendation, not a measured performance ranking.**

## Local environment and verification

The environment checks reported:

| Item | Observed value |
|---|---|
| Machine | MacBook Air, `MacBookAir10,1` |
| Chip | Apple M1 |
| Memory | 8 GB |
| CPU | 8 cores, 4 performance and 4 efficiency |
| macOS | 27.0, build `26A428` |
| Swift | Apple Swift 6.4 |
| Active SDK | `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` |
| Active developer tools | Command Line Tools |

This is a fanless, memory-constrained machine. Sustained energy use and memory pressure matter alongside latency.

### What was run

The checks used `system_profiler`, `sw_vers`, `swift --version`, and `xcrun --show-sdk-path`.

A small Swift probe imported AppKit, SwiftUI, and Speech. It compiled with `swiftc -O` and ran successfully. Its output was:

```text
AppKit, SwiftUI, and Speech linked successfully
Speech authorization status: 0
Legacy recognizer available: true
Legacy on-device recognition supported: true
SpeechTranscriber available: true
```

Authorization status 0 was not an authorization grant. The probe did not request permission, recognize audio, or launch a complete application UI.

The probe is temporarily located at:

```text
/private/var/folders/y9/hnkm2lv91n5chc4116wp_hf40000gn/T/opencode/vtt-native-probe/main.swift
```

Temporary files may not survive cleanup. This document preserves the observations, not a permanent benchmark implementation.

### What this establishes

- Native Swift framework compilation works with the installed Command Line Tools.
- The absence of full Xcode does not prohibit every SwiftPM or `swiftc` development path.
- Apple reports on-device recognition support on this machine.

### What remains unverified

- A complete MiniWhisper or reduced VTT build.
- Actual transcription through Apple Speech on this machine.
- Comparative latency, accuracy, memory, or energy across engines.
- Resource release after unloading CoreML models.
- A telemetry-free, reduced application build.
- Any claim that the recommended stack is the most efficient VTT on the market.

An earlier `xcodebuild -version` check failed because the active developer directory was Command Line Tools. No `Xcode*.app` was found under `/Applications`. No developer settings were changed.

## Stack comparison

These are architectural expectations, not measured memory rankings.

| Stack | Sources of overhead | Assessment |
|---|---|---|
| Swift + AppKit | Native framework state, application allocations, inference engine | Best default for a tiny macOS-only utility. |
| Swift + AppKit + occasional SwiftUI settings | Additional UI state and layout work when instantiated | Sensible. Do not rewrite working settings without measuring a benefit. |
| Rust + native AppKit bindings | Native framework state plus interoperability code | Comparable potential. More platform integration work, no automatic inference advantage. |
| Objective-C/C++ + AppKit | Direct native integration with ownership and interoperability complexity | Useful around existing C++ engines. Insufficient expected benefit to justify a rewrite by itself. |
| Rust + GPUI | Custom GPU-rendered UI and associated resources | Credible native alternative, especially for cross-platform plans. More renderer than a tiny pill needs. |
| Rust + Tauri | System WebKit processes, JavaScript, DOM, IPC | Good portability tradeoff, but unnecessary overhead for this macOS-only utility. |
| Electron | Chromium, Node, renderer and utility processes | Poor fit when low overhead outranks web-development convenience. |
| Flutter or Qt | Cross-platform UI machinery and rendering/framework state | Viable, but little benefit for this narrow target. Not benchmarked here. |
| Python or Node with native inference | Interpreter/runtime plus native bindings or a helper process | Useful benchmark tools. Not the preferred always-running application. |

[Tauri uses the system webview](https://v2.tauri.app/concept/process-model/). A small application download does not mean zero browser-process overhead.

[Electron's process model](https://www.electronjs.org/docs/latest/tutorial/process-model) includes Chromium and Node infrastructure.

Native applications can still waste resources through polling, retained models, and unnecessary audio processing. Choose the execution architecture, not the language reputation.

## Transcription engines

Evaluate engines behind the same minimal application so UI differences do not contaminate the comparison.

| Engine | Reason to test | Main tradeoff |
|---|---|---|
| FluidAudio + Parakeet TDT-CTC 110M | Smaller model candidate for English dictation | Accuracy must be established on the user's voice and technical vocabulary. Smaller does not guarantee lower end-to-end cost. |
| FluidAudio + Parakeet 0.6B v2 | Strong English-quality baseline matching the current context | Larger model and potentially more resident memory. |
| whisper.cpp with a small quantized English model | Mature native implementation and smaller-model choices | Accuracy and decoding latency may lose against Parakeet on this workload. |
| Apple SpeechAnalyzer / SpeechTranscriber | OS-managed local recognition and model assets | Proprietary engine, OS-dependent behavior, and less control over model versions. System-service memory still counts. |

For a reproducible, open-model application, start with FluidAudio. If only this Mac matters, Apple Speech is a legitimate benchmark competitor. A smaller app bundle does not establish lower total machine resource use.

Apple's Speech APIs do not expose a public "Parakeet authorization" choice. Speech recognition authorization, supported locales, on-device capability, and a request's dictation task hint are separate concepts. Do not assume Apple uses a particular underlying model without evidence.

### Smaller Parakeet candidate

FluidAudio's [TDT-CTC-110M documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/TDT-CTC-110M.md) reports:

- A fused preprocessor and encoder.
- 110 million parameters rather than 600 million.
- 96.5x overall real-time throughput on its M2 LibriSpeech test-clean evaluation.
- 3.01% word error rate on that evaluation.

These are upstream results, not measurements on this M1 or on technical dictation. Different documentation and artifact revisions report different file sizes. Download size, compiled artifact size, and resident memory must be measured separately.

Do not interpret memory figures for a vocabulary-boosting component as the footprint of the entire transcription pipeline.

### Neural Engine versus GPU

Start with CoreML's CPU/Neural Engine configuration as the battery-oriented candidate, not as a proven winner.

FluidAudio's [encoder compute-placement investigation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/EncoderComputePlacement.md) reports roughly 8% better end-to-end speed with GPU encoder placement in its tested configuration. Its preprocessor and decoder placement differ from the encoder placement.

That does not establish better energy efficiency on this M1. Measure energy per completed dictation, not only CPU percentage or instantaneous power. A higher-power engine that finishes sooner can sometimes use less total energy.

Lower precision is not automatically better. The same upstream investigation reports an INT4 encoder that was slower and less accurate than its shipped configuration.

### Native C++ alternative

[whisper.cpp](https://github.com/ggml-org/whisper.cpp) supports Apple Silicon acceleration, quantization, and CoreML encoder integration. CoreML encoder support does not imply every stage runs on the Neural Engine.

Benchmark the exact model, quantization, backend configuration, and release build. Do not compare model families by language implementation alone.

## The largest efficiency decisions

### 1. Model residency

| Policy | Benefit | Cost |
|---|---|---|
| Always loaded | Fast first dictation | Retains memory while the user works elsewhere. |
| Unload after each recording | Reduces retained model state | Reload latency and repeated initialization work. |
| Short warm cache | Reuses the model during bursts and releases it after inactivity | Requires a measured timeout and reliable lifecycle handling. |

**Prefer a short warm cache with memory-pressure handling.** Select its timeout experimentally rather than treating a guessed number as optimal.

Start loading at shortcut press so some loading overlaps with recording. Retain recorded audio safely if loading takes longer than the utterance.

Releasing Swift references does not prove that all CoreML, allocator, or driver memory disappears immediately. Measure the actual post-eviction footprint.

### 2. Transcribe once rather than repeatedly

The intended HUD has no live transcript.

For short dictations, record the audio and transcribe once at release. Avoid repeatedly reprocessing a growing recording to produce previews nobody sees.

For long recordings, bounded chunk processing may become worthwhile. That is a separate requirement, not a default. True incremental processing should also be distinguished from repeated full-prefix transcription.

### 3. Keep the idle app asleep

When idle:

- Stop microphone capture.
- Stop waveform and animation updates.
- Use event-driven shortcut and device notifications.
- Avoid periodic model scans, endpoint discovery, and stats refreshes.
- Do not run wake-word or command-recognition models.
- Avoid holding unnecessary settings windows and rendering resources alive.

A hidden window with an active timer is not an idle application.

### 4. Keep audio processing small

Use a bounded recording buffer and avoid unnecessary file conversion.

At 16 kHz mono Float32, audio occupies approximately 64 KB per second, or 3.84 MB per minute. Those are decimal units for the sample payload, not total process memory.

The microphone may supply another native format. Convert once rather than assuming the input device produces 16 kHz.

A level meter can reuse capture buffers. It does not need a second audio pipeline. Limit visual updates to what the small indicator actually needs.

### 5. Count external refinement costs

Moving refinement to Ollama makes the application bundle smaller. It does not reduce the total memory and compute consumed on the Mac.

For an 8 GB machine:

- Default to direct dictation and deterministic replacements.
- Make AI refinement explicitly optional.
- Include the external backend in resource measurements.
- Avoid keeping a local LLM loaded alongside the speech model without a demonstrated need.

Remote refinement moves inference off the machine but changes privacy, network latency, availability, and potentially cost. It is not equivalent to fully local processing.

### 6. Leave cheap features alone until measured

Ten text records, literal replacements, and occasional SQLite writes are unlikely to dominate this workload.

Prioritize model allocations, inference passes, background tasks, and audio lifecycle before deleting a useful history buffer.

Dependency count and source-file size are not direct measurements of runtime overhead. Likewise, removing an unused model from a download catalog does not reduce resident memory if it was never loaded. Removing unused engines can still simplify builds, distribution, and maintenance.

## Foundation comparison

### Recommended candidate: MiniWhisper

Repository: [andyhtran/MiniWhisper](https://github.com/andyhtran/MiniWhisper).

Inspected revision: `f89581a4f0acb59e6bb02b3389c47a6072190757`.

License: MIT, as declared by the project. Audit dependency and model licenses before redistribution.

Its inspected [Package.swift](https://github.com/andyhtran/MiniWhisper/blob/f89581a4f0acb59e6bb02b3389c47a6072190757/Package.swift) includes:

- macOS 14 minimum.
- Upstream FluidAudio.
- A Whisper binary target.
- Sparkle.
- Separate application and CLI executable targets.
- A test target.

Its [Parakeet provider](https://github.com/andyhtran/MiniWhisper/blob/f89581a4f0acb59e6bb02b3389c47a6072190757/Sources/MiniWhisper/Services/ParakeetProvider.swift) exposes initialization, transcription, and unloading. It initializes Parakeet v3 in the inspected version. Testing v2 or 110M requires adaptation rather than assuming an existing setting.

The repository also contains audio-device handling, event-tap and shortcut components, and application lifecycle code. It is a more focused starting point than FluidVoice, not an already proven resource-use winner.

For a reduced fork:

1. Establish a working baseline before deleting features.
2. Retain audio capture, shortcuts, permissions, and insertion.
3. Keep one engine in the distributed build after benchmarking.
4. Remove unnecessary audio retention and conversion.
5. Add explicit model eviction and raw-text recovery policies.
6. Create settings only when opened.
7. Preserve useful tests and platform workarounds.
8. Use independent branding, bundle identifiers, and release/update configuration.

The existing code still needs a lifecycle and correctness audit. An `unload()` method is not proof of complete resource reclamation.

### Native Rust alternative: HEX

Repository: [anomalyco/hex](https://github.com/anomalyco/hex).

Inspected revision: `efd9d6574ede40f1315373c6437cad7ddbb723b1`.

License: MIT, as declared by the project.

The current [Cargo.toml](https://github.com/anomalyco/hex/blob/efd9d6574ede40f1315373c6437cad7ddbb723b1/Cargo.toml) uses Rust, GPUI, and `transcribe.cpp`. It is not a Tauri application. It also includes features beyond the proposed minimal dictation scope.

Its [historical benchmark report](https://github.com/anomalyco/hex/blob/efd9d6574ede40f1315373c6437cad7ddbb723b1/docs/research/transcription-benchmark.md) compares ONNX Int8 against `transcribe.cpp` Metal Q8 on an M2 Max:

| Metric | ONNX Int8 | Metal Q8 |
|---|---:|---:|
| Median clip time | 368 ms | 216 to 234 ms |
| p95 clip time | 509 ms | 303 to 356 ms |
| Peak resident memory | 1.73 GB | 1.05 GB |
| Provisional WER | 8.07% | 9.82% |

These results are explicitly historical and provisional. The report describes corpus limitations, including references derived from earlier model transcripts. It also notes that current model defaults differ from the historical experiment.

This is useful evidence that backend selection can materially affect performance. It is not evidence that Rust beats Swift, that current HEX reproduces those figures, or that Metal beats FluidAudio on this M1.

Use HEX as the native-Rust comparison candidate.

### FluidVoice

Repository: [altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice).

Previously inspected revision: `0039d645aa6bec8c7c6f571785bf4b5b7fa2a29b`.

FluidVoice remains a strong complete-product reuse candidate, but it is not the first choice under the revised minimal-runtime goal.

Source findings from the earlier investigation:

- Native Swift application with substantial audio, shortcut, focus, and insertion handling.
- GPLv3 application license.
- macOS 15 minimum.
- Uses an `altic-dev/FluidAudio` fork rather than upstream FluidAudio.
- Private enhancement provider has a compile-time boundary and unavailable-provider defaults.
- Analytics collection and upload exist. Disabling detailed analytics is not the same as zero telemetry according to its README.
- Relevant dictation, audio recovery, shortcut, and clipboard tests exist.

A reduced fork would need actual removal of unwanted activity rather than hidden settings. Its value is mature integration and tests; its cost is broader coupling and ongoing fork maintenance.

### Other candidates reviewed

| Project | Findings | Reason not selected first |
|---|---|---|
| Handy | MIT; Rust/Tauri/React; local inference and substantial clipboard handling | Webview architecture and cross-platform scope do not match the lowest-overhead macOS-only target as closely. |
| VoiceInk | Native Swift; upstream FluidAudio; project declares GPLv3; broader dictation product | More product and distribution plumbing than needed. It remains a credible reuse option. |
| Quill | MIT; Swift/SwiftUI; FluidAudio and WhisperKit; MLX refinement and bundled Harper CLI | Its current feature and dependency scope is broader than its minimal-daemon description suggests. |
| VoiceScribe | MIT; Swift; FluidAudio, WhisperKit, MLX cleanup, and Composable Architecture | Broader inference and state-management dependencies than this project needs. |

Sources:

- [Handy](https://github.com/cjpais/Handy)
- [VoiceInk](https://github.com/Beingpax/VoiceInk)
- [Quill](https://github.com/imtamiliniyan/quill)
- [VoiceScribe](https://github.com/eddmann/VoiceScribe)

Repository popularity and small source size were not treated as performance measurements. This was a targeted comparison, not an exhaustive survey of every VTT application.

## Benchmark definition

There is no single implementation that automatically minimizes memory, cold-start latency, energy, and recognition errors simultaneously.

Use this decision rule:

> Choose the lowest-energy implementation that meets the user's accuracy and release-to-paste latency requirements without causing unacceptable memory pressure.

Set the acceptable latency and accuracy thresholds before selecting the winning engine. Do not choose thresholds after seeing which candidate wins.

### Measurement matrix

Compare release builds using the same independently transcribed recordings.

| Measurement | Purpose |
|---|---|
| Idle CPU and wakeups | Detect polling, animation, or audio work while unused. |
| Idle physical memory footprint | Measure the application's background cost. |
| Cold model load | Expose first-use and post-eviction costs. |
| First dictation latency | Capture the user's initial experience. |
| Warm median and p95 release-to-paste latency | Measure typical and slow interactive response. |
| Peak memory | Detect pressure during inference. |
| Memory after eviction | Verify model-retention policy. |
| Energy over repeated dictations | Compare total processing cost rather than instantaneous power. |
| Word errors and technical-term errors | Prevent low-resource but unusable recognition from winning. |
| Performance with editor and browser running | Reflect the real 8 GB working environment. |

Include helper processes, local refinement servers, and attributable system-service work. App-only RSS can make an implementation look efficient merely by moving work elsewhere. Avoid double-counting shared memory when aggregating processes.

### Controls

- Record speech once and reuse identical input files.
- Use human references rather than another engine's output.
- Include short phrases, longer dictation, names, numbers, technical terms, silence, and ordinary background noise.
- Keep model revision, precision, decoder settings, and engine revision fixed and recorded.
- Separate first installation/compilation, cold loading, and warm inference.
- Alternate candidate order and repeat runs.
- Record power mode, thermal state, and competing workloads.
- Test both sparse use and bursts of dictation.
- Validate insertion separately so model timing is not confused with clipboard delays.
- Test cancellation, target changes, and repeated sessions alongside performance.

Published M2 or M2 Max benchmarks are useful screening evidence. They are not substitutes for measurements on this M1.

## Proposed next work

1. Build a pinned MiniWhisper baseline without changing its inference backend.
2. Verify direct transcription, shortcuts, insertion, cancellation, and recovery.
3. Add repeatable resource and latency measurements.
4. Benchmark FluidAudio 110M against 0.6B v2 with the same corpus.
5. Compare the selected candidate against native C++/Metal and Apple Speech.
6. Choose the model and retention policy from accuracy, latency, energy, and memory results.
7. Remove unused engines and background behavior in small, verified changes.
8. Recheck the packaged application, including its helper processes and update behavior.

No market-leading performance claim is justified until that work is complete.

## Related corrections to the context

- Move safety-buffer persistence ahead of refinement and insertion in the implementation sequence rather than deferring it to the final phase.
- Treat clipboard paste as a broadly compatible mechanism, not universally confirmed delivery.
- Preserve newer user clipboard changes during restoration.
- Do not equate external LLM integration with zero machine overhead.
- Keep the model backend and its retention policy explicit rather than assuming CoreML alone determines resource use.

## Bottom line

**Swift/AppKit plus one carefully managed native inference engine is the recommended architecture. A reduced MiniWhisper fork is the first foundation to validate.**

The largest likely gains come from doing less inference, keeping idle code asleep, and retaining less model state. Replacing Swift with Rust is not justified without a measured benefit.

The recommendation applies the poteto principles of Laziness Protocol by avoiding an unsupported language rewrite, and Prove It Works by leaving final performance claims contingent on local measurements.
