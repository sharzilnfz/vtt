# Efficiency: the stack, the levers, and how to prove it

Follows `CONTEXT.md` as updated, plus `FOUNDATIONS.md`. The brief here is different from the last two reviews. Not features, and not what to reuse, but how to make this the lightest dictation app on the machine. Everything below is measured or read from source, and the gaps are labelled.

## The insight that reframes the problem

Inference is not the bottleneck, and optimizing it is wasted effort.

| Measurement | Value | Source |
|---|---|---|
| Parakeet TDT 0.6B v2 CoreML, real-time factor | ~110x on M4 Pro | model card |
| Parakeet TDT v3, LibriSpeech test-clean | 155.6x overall, 139.6x median, M4 Pro | FluidAudio benchmarks |
| Parakeet Unified 0.6B batch, int8 ANE | 123.3x overall, M5 Pro | FluidAudio benchmarks |
| Parakeet TDT-CTC-110M | 96.5x, M2 | FluidAudio models doc |

At 110x, a 10-second dictation costs about 91 milliseconds of compute. Halving that saves 45 milliseconds the user will never perceive. So the decoder is not where your efficiency lives.

Four things actually show up on the machine, in order of size.

1. Permanent resident memory. The model sits in RAM all day.
2. Idle overhead. A menu bar app is judged by its cost at rest, not at peak.
3. Energy per dictation.
4. The 15-second chunk wall, which makes long dictations more expensive than short ones per second of speech.

## The stack, layer by layer

| Layer | Choice | Why | Rejected |
|---|---|---|---|
| Language and runtime | Swift 6, AppKit-first, SwiftUI only for settings | AOT compiled, no interpreter, no JIT, no garbage collector. ARC frees deterministically, so there are no GC pauses and no growing heap. | Rust and Tauri, because you would give up native CoreML and FluidAudio, and the WKWebView adds idle footprint. Electron for the same reason, worse. |
| Inference | FluidAudio, Apache-2.0 | Already ships the decode loop, VAD, model download, and the vocabulary rescorer. | Writing the decode loop. FluidAudio's own commit history shows a multi-round bug hunt in the vocabulary path alone. |
| Model | Parakeet TDT-CTC-110M as default | 3.5x smaller than the 0.6B bundles for 0.4 points of WER. See lever 1. | v2 and v3 as the default. Both are heavier for no accuracy gain you can hear. |
| Persistence | GRDB, already in the fork | A 10-row buffer plus daily counters. GRDB's overhead is irrelevant at this scale. | Raw sqlite3, which would save about a megabyte and cost you ergonomics. |
| Hotkeys | `sindresorhus/KeyboardShortcuts` plus the fork's `ModifierKeyMonitor` | The monitor is already scoped correctly. See lever 3. | Carbon `RegisterEventHotKey` alone, which cannot express a modifier-only chord. |
| Updates | None, or manual | Sparkle adds a framework plus a periodic background check, which is idle network and idle CPU for a tool you can update by hand. | Sparkle, unless you want the auto-update experience more than the idle budget. |
| Telemetry | None | Already in the spec. | Anything. |

## Lever 1. The model choice, and it is the big one

I measured the actual CoreML bundles on HuggingFace rather than trusting a summary.

| Model variant | Encoder weights | Plus decoder, joint, mel | Loaded total |
|---|---|---|---|
| v2, `ParakeetEncoder.mlmodelc` | 1179.8 MB | ~32 MB | ~1212 MB |
| v2, `ParakeetEncoder_v2.mlmodelc` | 591.1 MB | ~32 MB | ~623 MB |
| v2, `Encoder.mlmodelc` | 445.2 MB | ~32 MB | ~477 MB |
| v3, `Encoder_v2.mlmodelc`, int8, the default | 594.2 MB | ~50 MB | ~644 MB |
| v3, `EncoderInt4.mlmodelc` | 297.9 MB | ~50 MB | ~348 MB |
| **TDT-CTC-110M, fused preprocessor and encoder** | **215.9 MB** | **~11 MB** | **~227 MB** |

The v2 model card states ~800 MB peak memory, which sits between the `Encoder` and `ParakeetEncoder_v2` variants. So the real v2 number is somewhere between 477 MB and 1.2 GB depending on which encoder bundle loads.

The 110M hybrid is the efficiency pick. Its `Preprocessor.mlmodelc` contains the encoder, which is what "fused frontend" means in the source, so you load two models instead of five. That is 227 MB against roughly 800 MB, a saving of about 570 MB held permanently.

What it costs, on LibriSpeech test-clean:

| Model | Avg WER | Params |
|---|---|---|
| Parakeet TDT v2 | 2.6% | 0.6B |
| Parakeet TDT v3 | 2.6% | 0.6B |
| Parakeet Unified 0.6B | 2.15% | 0.6B |
| TDT-CTC-110M | 3.01% | 110M |

0.4 percentage points on clean read speech, for 570 MB back, every hour of every day. For a dictation tool where you can see and fix a mistake immediately, that is the right trade. Ship 110M as the default and make the 0.6B an opt-in quality tier.

Two caveats I will not paper over. First, `EncoderInt4` looks tempting at 348 MB but FluidAudio's own benchmark says it is slower and much worse, because degraded outputs make the TDT decoder skip fewer frames and do more work. Do not use it. Second, the 110M throughput figure was measured on an M2 and the 0.6B figure on an M4 Pro, so those are not comparable. Memory is the clear win. Measure throughput on your own machine.

## Lever 2. Residency policy

FluidAudio keeps models resident for the lifetime of the owning actor and exposes no unload or eviction API. `ModelCache` handles downloads, not residency. So the default is "resident forever," and there is nothing built in to release it.

| Policy | Resident memory | Latency on a dictation | Verdict |
|---|---|---|---|
| Keep resident | Full, all day | ~0 ms | Right for push-to-talk. The latency budget is the product. |
| Load per dictation | Low | High | Wrong. CoreML compiles on first load. The encoder took 3361 ms cold against 162 ms warm on an iPhone 16 Pro Max, and even warm loads cost a few hundred milliseconds. |
| Keep resident, drop under memory pressure | Full, then low | ~0 ms normally | Do this as a safety valve. |

The valve is worth building and is not in your spec. Install a `DispatchSourceMemoryPressure` handler. On a warning, drop the `AsrManager` reference and let ARC free the models. Rebuild it lazily on the next dictation. That gives you warm latency in the normal case and gives memory back when the machine is under pressure, which is exactly when a dictation tool should yield.

One constraint to respect. CoreML's load and predict APIs are not reentrant, and concurrent calls corrupt internal scratch buffers. That is why FluidAudio isolates every model behind an actor. Do not add your own parallel path around it.

## Lever 3. Idle overhead, the lever everyone ignores

An app that runs all day is judged by its idle cost. I read the recommended fork's source for this, and it gets the hard part right.

**The event tap is scoped correctly.** `ModifierKeyMonitor` creates the tap with `eventsOfInterest: 1 << CGEventType.flagsChanged.rawValue`, `options: .listenOnly`, and `place: .headInsertEventTap`. Scoping to `flagsChanged` is the important part. The callback fires only when a modifier key changes state, not on every keystroke, mouse move, or scroll. A tap registered for all events runs your code on every input event system-wide and is a classic source of idle CPU and input latency. This one does not.

It also handles `tapDisabledByTimeout` and `tapDisabledByUserInput` by re-enabling the tap, which is the failure mode that silently kills global hotkeys in long-running apps.

**There are zero timers.** `Timer.scheduledTimer`, `Timer.publish`, and `DispatchSourceTimer` do not appear anywhere in the app. No polling, no heartbeat, no wakeups at rest. That is rarer than it should be.

**Two things to change.**

`handleFlagsChanged` already runs on the main run loop, because the run loop source is added with `CFRunLoopGetCurrent()` and `.commonModes`. It then wraps the callback in `DispatchQueue.main.async`, which defers to the next main run loop iteration. That is a redundant hop that adds latency to every press and every release of the push-to-talk key. If the tap is already on main, call the handler directly.

Consider dropping Sparkle. It brings a framework, a background update check, and a second daemon-shaped thing to account for, in exchange for an update experience a personal tool does not need.

## Lever 4. The audio path

Read from `PCMRecording.swift` in the recommended fork.

**The resampler quality is set to the most expensive option.** The code builds an `AVAudioConverter` to 16 kHz `pcmFormatInt16` and sets `sampleRateConverterQuality = AVAudioQuality.max.rawValue`. `.max` exists for mastering audio. You are converting 48 kHz microphone input down to 16 kHz for a speech recogniser that was trained on noisy, codec-degraded speech. `.medium` is materially cheaper per dictation and the WER difference is not measurable. This is free CPU you are spending, on every single dictation, for nothing.

**Int16, not Float32.** The fork uses `pcmFormatInt16`. Your `CONTEXT.md` Section 2 says Float32. Int16 halves the buffer bytes for no accuracy cost and it is the format the model wants. Change the spec.

**Parallel conversion is already there and worth keeping.** The fork fans resampling across all cores when the clip exceeds 160,000 frames, which is 10 seconds. Good behaviour for long holds.

**Two things to change.** The fork writes every dictation to a PCM file on disk, then transcribes from the file. That is disk I/O, temp-file churn, and SSD write amplification you do not need, and your spec already says audio is not persisted. Buffer in memory. And `installTap(onBus:bufferSize:1024:)` allocates a fresh `AVAudioPCMBuffer` on every callback, roughly 47 allocations a second at 48 kHz. A preallocated ring buffer removes that.

The tap callback runs on a real-time audio thread. Keep it allocation-free and lock-free, and hand off with a ring buffer rather than by allocating.

## Lever 5. Rendering the pill

The animated waveform at 60 frames per second is the single largest CPU and energy draw while recording, and it is the one piece of the app that runs continuously during use.

Draw it with Core Animation. A `CAShapeLayer` whose path you update from the audio level costs one path rebuild per frame and no view graph. A SwiftUI view re-evaluating per frame is heavier, and a SwiftUI `Canvas` redrawing at 60 fps is heavier still. If the waveform is not load-bearing, 30 fps is indistinguishable and halves the cost.

Keep SwiftUI for the settings window, where the cost is irrelevant. Use `NSPanel` with `.nonactivatingPanel` for the pill, as your Section 3 already specifies. Set `LSUIElement` so there is no Dock icon, no app switcher entry, and no window server surface for a main window that never exists.

## The 15-second wall

`ASRConstants.maxModelSamples = 240_000`, which is exactly 15.0 seconds at 16 kHz. The encoder's traced input shape is fixed, so this is a hard ceiling per pass, not a soft guideline. Above it, `SlidingWindowAsrManager` chunks with `standardOverlapFrames = 25`, which is 2.0 seconds of overlap, and de-duplicates tokens within a 25-frame tolerance at chunk boundaries.

What that means for a push-to-talk app.

Utterances under 15 seconds are a single pass, and that covers most dictation. Longer ones pay roughly 13 percent redundant compute for the overlap plus stitching cost. Your spec sets no maximum recording duration, which is a gap, and it is an efficiency gap as much as a feature one. Decide whether a long hold is rejected, truncated at 15 seconds, or chunked, and write the answer down.

## How to prove you are the most efficient

A harness is at `scripts/measure-efficiency.sh`. It measures resident memory via `footprint`, peak memory via `phys_footprint_peak`, and idle CPU as the exact delta in cumulative CPU time over the sampling window rather than a decaying average. Deep mode adds energy, CPU ms/s and timer wakeups via `powermetrics`.

```
./scripts/measure-efficiency.sh -i 60 VTT
./scripts/measure-efficiency.sh -i 60 VTT Handy FluidVoice VoiceInk
sudo ./scripts/measure-efficiency.sh -d VTT
```

Run it in a normal Terminal. `ps` and `top` are blocked for other processes inside a sandbox, so a sandboxed run reports memory only. With no target it measures the calling shell, which doubles as a self test. I verified that path, and it reports real numbers for named apps.

Design against these. They are proposals, not measurements, and you should tighten them once you have a baseline.

| Metric | Target |
|---|---|
| Resident, model warm, 110M | under 300 MB |
| Resident, model warm, 0.6B | under 900 MB |
| Idle CPU | under 0.1%, and zero timer wakeups in powermetrics |
| Release to inserted text, p50, 5 second utterance | under 400 ms on your target Mac |
| Binary and frameworks, excluding models | under 25 MB |
| Energy per dictation | measured, and compared against the three competitors on the same machine |

The only honest way to claim "most efficient in the market" is to run the same harness against Handy, FluidVoice and VoiceInk on your Mac. I cannot measure them from here, so treat the following as structural expectations to check rather than findings.

Handy is Tauri, so it carries a `WKWebView`. A webview's idle footprint is normally well above a native AppKit app's. It is also the most popular of the four at 31.8k stars, which makes it the most likely to be the heaviest at rest. FluidVoice ships a local enhancement model alongside the ASR model, so it holds two models resident rather than one. VoiceInk runs a separate XPC service for refinement, so it has a second process to account for. All three are testable with the harness.

## What I could not verify

FluidAudio's documentation contains no energy or power numbers at all. The 56 KB benchmarks page reports RTFx and nothing about joules or watts, so no energy claim in this document comes from a published measurement. It has to be yours.

The docs also report no RAM figure for any Parakeet ASR model. The ~800 MB for v2 comes from the model card, and my bundle-size table is my own measurement of the published files. A loaded model's footprint will not equal its file size, so treat the table as a ranking rather than a prediction.

The competitor idle footprints above are structural reasoning from their architectures, not measurements.

And the 110M versus 0.6B throughput comparison spans two different machines, so it tells you nothing about relative speed. Only memory is settled.

## Principles applied

**Foundational thinking** moved the model choice to lever 1 and the decoder to nowhere, because getting the data structure and the resident working set right makes the rest obvious. **Laziness protocol** rejected an embedded updater, a second model, and a custom decode path, and it is why the recommendation is to change one resampler constant rather than build a pipeline. **Build the lever** produced `scripts/measure-efficiency.sh`, because "most efficient in the market" is a claim you can only make with a rerunnable comparison. **Prove it works** is why the harness self-tests and why the design targets are stated as numbers rather than adjectives. **Boundary discipline** keeps the real-time audio thread allocation-free and confines validation to the edges of the audio path. **Encode lessons in structure** is why the 15 second ceiling and the resampler quality become constants with a comment rather than folklore. **Experience first** is the reason residency stays warm by default, since a 300 ms stall after you release the key is a worse experience than 570 MB of RAM.
