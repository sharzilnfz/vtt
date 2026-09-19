# Utter review: gaps, architecture rating, plan rating

Reviewed: `CONTEXT.md` (5 spec sections, 5 ADRs). The project directory contains no code and no git history, so the specification is the artifact under review.

Stated goal, verbatim: "a very minimal, completely free and open source speech-to-text app similar to Handy and Fluid Voice." Minimal, free, open source, comparable to two named competitors. Those are the acceptance criteria everything below is measured against.

## Verdict

| Dimension | Rating | One line |
|---|---|---|
| Product spec (the vision) | 8/10 | Unusually disciplined scope. The ADRs reject the right things. |
| Architecture | 5.5/10 | Good taste, half-built. Three boundaries are wrong or absent. |
| Plan | 2/10 | There is no plan. There is a feature inventory. |

The ceiling here is not judgment. It is coverage. The document spends its detail budget on stats, a vocabulary file format, and a model download UI, and one line each on text insertion and audio capture. The parts it details do not decide whether the app works. The parts it handwaves do.

## Method

Read `CONTEXT.md` in full. Then ran three independent architecture critics on the same prompt at three model tiers (reasoning, default, fast), so agreement across them is signal and a single voice is a hypothesis. Then verified the load-bearing external claims myself rather than trusting the critics' summaries.

## Verified ground truth

The document asserts things about the outside world. Most hold. Two do not.

| Claim in CONTEXT.md | Reality | Verdict |
|---|---|---|
| `parakeet-tdt-0.6b-v2-coreml` is the STT pipeline | The model exists as a CoreML build for Apple Silicon, ~110x RTF on M4 Pro, ~800 MB peak, macOS 14+. But it is a directory of 12+ separate artifacts (encoder, decoder, joint, mel, vocab), not a runnable unit. | Partly true |
| Section 7's stack is "CoreML pipeline using existing models" | A runtime must own the TDT greedy-decode loop, encoder state, chunk stitching, and token-to-vocab mapping. The document never names it. The de-facto implementation is FluidAudio, Apache-2.0, which ships exactly this plus VAD, model download, and vocabulary rescoring. | Gap |
| Section 5: vocabulary "injected as context prompt hints to the transcription step" | Parakeet TDT is a transducer with no prompt encoder. There is no such hook. FluidAudio's real mechanism is CTC keyword spotting plus rescoring (`CtcKeywordSpotter`, `VocabularyRescorer`, `CustomVocabularyContext`). | Contradicted |
| Section 7: insertion via `AXUIElement` with synthetic event fallback | AX has no insert-at-cursor primitive. Writing the value attribute replaces the whole field. Browsers, Electron apps, and terminals do not expose spliceable text. Secure Event Input blocks synthesized events. Handy, the named benchmark, uses clipboard paste and restores the prior clipboard. | Contradicted |
| Section 2: keybind `Left Control + Left Option` | Confirmed as the default VoiceOver modifier on macOS. The app would fight the screen reader. | Confirmed, collision |
| Models are usable in a free redistributable app | Parakeet is CC-BY-4.0 (attribution required), Silero VAD CoreML is MIT, FluidAudio is Apache-2.0. Compatible, but attribution needs a surface in the UI. | Confirmed, obligation |
| Handy and Fluid Voice | Handy is Tauri/Rust, MIT, clipboard paste, configurable hotkey, Whisper GGML plus Parakeet. FluidVoice is native Swift, GPLv3, built on FluidAudio, configurable hotkey, multilingual Parakeet v3. | Confirmed |
| Three TCC grants are needed | Microphone, Accessibility, and Input Monitoring. TCC binds grants to code signature, bundle ID, and path, so an ad-hoc-signed rebuild loses them every time. | Confirmed, undocumented |

Sources: [FluidAudio](https://github.com/FluidInference/FluidAudio), [parakeet CoreML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml), [Handy](https://github.com/cjpais/Handy), [VoiceOver commands](https://support.apple.com/guide/voiceover/general-commands-cpvokys01/mac), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Gaps

Ordered by how much each one costs. Structural means it blocks shipping or forces a rewrite.

### Structural, wrong as specified

**G1. No permission, signing, or distribution model.** The app needs three TCC grants. TCC keys each grant to the code signature, bundle ID, and on-disk path, so an unsigned or ad-hoc build drops all three on every rebuild and every time the `.app` moves. Notarization avoids that and requires a paid Apple Developer account, which sits awkwardly against "completely free" for the maintainer. Unnotarized means Gatekeeper shows "app is damaged" and the user runs `xattr`. Both named competitors ship Homebrew casks. This is the single largest risk to the "comparable to Handy and Fluid Voice" criterion, and it constrains bundle ID, update mechanism, and contributor workflow. It must be decided before any app code.

**G2. Text insertion is the wrong mechanism, and it is the product.** `AXUIElement` has no insert-at-cursor. Setting the value attribute destroys existing field content, the selection, and the undo stack. Chromium and Electron apps (Chrome, Slack, VS Code, Discord) do not expose settable text in the AX tree at all. Terminals do not either. The universal channel is clipboard plus a synthesized Cmd+V, which mutates the user's clipboard as a side effect the document never mentions. Handy ships exactly that, with save and restore. So the document's stated primary fails in the apps people dictate into most, and its "fallback" is the real mechanism. There is also no success predicate, yet Section 3 promises "dismisses immediately upon insertion" and Section 2 promises a "soft pop sound upon successful injection." Neither path reports success, so the cue is unimplementable as written.

**G3. Nothing owns the decode loop.** Section 7 names model artifacts and calls them a pipeline. The work between audio samples and text (TDT greedy decode, encoder state, chunk stitching, mel alignment, token-to-vocab) is nontrivial and unassigned. FluidAudio already ships it, Apache-2.0, along with Silero VAD, a `ModelHub` downloader with an offline mode, and the vocabulary rescorer. ADR 001's rejection of an in-app catalog is the right call, but FluidAudio's `ModelHub` means the hand-rolled Section 6 downloader duplicates the SDK the app would depend on anyway.

**G4. The vocabulary seam connects to nothing.** Section 5's "context prompt hints" describes a Whisper capability. Parakeet TDT has no prompt encoder. Worse, Mode 1 has no LLM step at all, so even if the hook existed, Direct Dictation has no destination for it. The regex substitution half is sound. ADR 005 declares a seam that only exists as the lossy half, so acronym accuracy in the primary mode is unaddressed.

**G5. Mode 2 has no failure path, and its safety net loses the raw transcript.** Refinement is a synchronous HTTP round trip between transcription and insertion, with no specified timeout, no behavior on connection refused, no fallback to the raw text, no Keychain for credentials, and no statement that the user's speech leaves the machine. Section 3 lists four pill states and none of them is failure. The safety net saves refined text only in Mode 2, so when refinement fails there is no state where the raw transcript survives. That is data loss in the exact scenario ADR 004 exists to prevent.

**G6. The model ingest contract is unbounded.** ADR 001 makes the app a generic loader (any folder drop, any URL, `.mlmodelc.zip` or `.bin`) while Section 7 hard-codes two artifacts with a fixed tensor contract. There is no manifest, no checksum, no version gate, no capability declaration. A single `.mlmodelc.zip` URL also does not match how these models publish, which is a multi-file tree. Section 6 defines two model directories with no precedence rule, so "which model will load" has no answer.

**G7. No error state exists anywhere.** Section 3 defines `{hidden, expanded, pulsing, dismissed}`. The pipeline needs `{recording, transcribing, refining, inserting, failed}`. Microphone denied, model missing, empty transcript, insertion failed, endpoint unreachable: none are modeled. Combined with "zero text rendering on screen," every failure mode is silent. The user cannot tell whether the app worked. The zero-text decision is defensible on its own, and it becomes a bug in combination with silent failure.

### Structural, missing entirely

**G8. The audio subsystem has no design.** "Microphone captures audio while held" is the whole specification for the core loop. Unstated: sample rate and format (Parakeet needs 16 kHz mono), resampling, buffer strategy, and whether transcription is streaming or batch-on-release. That last one is the central design question for the audio module and it is not answered. `silero-vad-coreml` is named as pipeline infrastructure while push-to-talk already supplies utterance boundaries, so VAD is a dependency with no defined job.

**G9. No re-entrancy rule.** What happens if the user holds the key again while Mode 2 is still refining? Two in-flight transcriptions would write to the same SQLite table and the same target field. Nothing in the document serializes or rejects that.

**G10. `history.db` stores every dictation in plaintext, forever.** The metrics listed (words today, this week, all time, time saved) need aggregates only. `content` is not required for any displayed number, yet it lives in the same unbounded table with no retention policy, no encryption, no secure-field exclusion, and no index on `timestamp` despite every query being time-ranged. ADR 004 justifies the table as a 10-item safety buffer, which is a different data model from a lifetime stats log. One table serves two incompatible consumers. For a privacy-first app, this is a persistent plaintext record of everything dictated, surfaced in the menu bar.

**G11. No definition of done, no budget, no verification strategy.** "Minimal, free, open source, like Handy and Fluid Voice" is a direction, not a criterion. There is no latency target (release-to-inserted-text), no accuracy target, no list of apps that must work, and no tests of any kind. The verification surface for this product is cross-app and manual, which means the harness has to be built deliberately. Nothing in the document proposes one.

### Concerns

**G12. Hotkeys collide and are hardcoded.** Control+Option is the VoiceOver modifier, so the primary bind fights the built-in screen reader. That hits exactly the population this tool serves. Both binds are fixed while both competitors make the hotkey configurable. The two chords also share Left Option and differ only in the second key, so holding Ctrl+Opt and then adding Cmd matches the refined chord, and releasing in the other order does not. No precedence or debounce rule is defined. A modifier-only chord cannot use `RegisterEventHotKey`, so it needs a `flagsChanged` event tap, which is permission-gated and can be disabled by the OS under load.

**G13. Paths follow Linux convention.** `~/.config/utter/` is wrong for macOS. The convention is `~/Library/Application Support/utter/`. Cheap to fix now, annoying later.

**G14. No attribution surface.** Parakeet is CC-BY-4.0, so a redistributable app must display attribution. There is no surface for it in Section 3 or Section 6. The app's own license is never stated either, which matters for a project whose headline claim is "open source."

**G15. Language scope is silently English-only.** `parakeet-tdt-0.6b-v2` is English-only. v3 is the multilingual sibling and both competitors offer it. Because of G6, swapping later is not a config change.

**G16. No first-run experience.** On a fresh install there is no model and no permissions, so the app does nothing. There is no onboarding flow, no model download on first run, and no permission walkthrough.

**G17. No update mechanism and no diagnostics.** No Sparkle, no manual update story. No log file and no "last error" surface in the menu bar, for a product whose failures are silent by design.

### The ADR gap

The five ADRs record the peripheral decisions and skip the foundational ones. There is an ADR for rejecting a model catalog and an ADR for the vocabulary seam. There is no ADR for:

- Native Swift versus Tauri, when the named benchmark (Handy) is Tauri.
- Parakeet versus Whisper, when the named benchmark supports both.
- Push-to-talk versus toggle-to-record.
- CoreML versus MLX or whisper.cpp.
- Batch versus streaming transcription.
- The text insertion mechanism, which is the highest-risk decision in the document.

The easy calls got written down. The hard ones got one line each in Section 7.

## Architecture rating: 5.5/10

Scored against the standard architectural lenses. Each lens is judged on the specification, not on a hypothetical implementation.

| Lens | Score | Reasoning |
|---|---|---|
| Abstraction fit | 5/10 | ADR 001 and 002 correctly delete two large abstractions. But there is no abstraction for the STT runtime (G3), no routing abstraction for insertion (G2), and ADR 005's vocabulary seam is a seam to a hook that does not exist (G4). The app-to-SDK boundary is undefined. |
| Data model | 5/10 | The schema covers the listed metrics. But `content` is retained forever, the buffer and the lifetime log share one table, the in-memory and on-disk buffers have no reconciliation rule, and the audio data shape is unspecified. Model resolution has two directories and no precedence. |
| Boundary discipline | 3/10 | The weakest lens. Three external boundaries need contracts and none has one: the TCC-gated capabilities (no permission state model), the insertion boundary (no success predicate, no error taxonomy), and the HTTP refinement boundary (no timeout, no fallback, no credentials, no disclosure). Validation and error handling live nowhere because they were never designed. The plain-text boundaries (`vocabulary.txt`, model directories) are correctly treated as external input. |
| Evolution readiness | 5/10 | Swapping the model is not a config change because the pipeline contract is undefined. Adding a language means replacing the model and the vocabulary mechanism. Insertion is baked into the UX once chosen. Offset by strong scope discipline: there is little speculative code to unwind, and the ADR format gives new decisions a clean home. |
| Complexity vs value | 6/10 | Right instinct, wrong allocation. A hand-rolled URL downloader duplicates FluidAudio's `ModelHub`. VAD is a dependency with no job. Stats get a full SQLite schema while audio capture gets one sentence. |
| Consistency | 6/10 | Internally coherent about minimalism, and the ADR format is genuinely good. Undercut by the "zero network" posture coexisting with Mode 2's default network egress and no disclosure, and by `~/.config` against otherwise macOS-correct instincts. |

Average 5.0. I am rounding up to 5.5 because the ADRs are real engineering work and the scope discipline is better than most funded products. The score is capped by coverage, not by judgment. As a product spec this is an 8. As an architecture it is a good sketch that is roughly half-built, and the missing half is the half that decides success.

## Plan rating: 2/10

There is no plan. `CONTEXT.md` is a feature inventory plus five ADRs. Measured as a plan, every element is absent:

- No phasing. Everything is in scope simultaneously.
- No ordering. Nothing says what ships first.
- No risk-first sequencing. The riskiest question (does text actually land in Chrome, Slack, VS Code, and Terminal?) is not scheduled first, and it is the question that can kill the project.
- No definition of done. No latency target, no accuracy target, no app support matrix.
- No verification strategy. Zero tests, zero harness, for a product whose correctness is cross-app and manual.
- No milestones and no v0.1 boundary.
- No budget for the two numbers that determine whether this beats Handy: release-to-insert latency and word error rate on technical vocabulary.

It is 2 and not 0 because the ADRs exist. Recording decisions in a durable format is more than most plans do, and it means the fix is cheap. This is the highest-value, lowest-cost gap in the document. An hour of writing retires it.

## The plan it should have

Ten phases. Small, ordered so infrastructure and shared types land first, and risk first.

**Phase 0, spike.** Throwaway code. Prove the three boundaries that can kill the design, before any architecture exists.
- 0a. FluidAudio plus Parakeet v2 transcribes a WAV on this machine. Record RTF and peak memory.
- 0b. Insert text into six apps (TextEdit, VS Code, Chrome, Slack, Terminal, Notes) via clipboard + Cmd+V and via AX. Record what works and what does not.
- 0c. Capture Ctrl+Option as a push-to-talk tap. Confirm the TCC prompts appear and that grants survive a rebuild under a stable signing identity.

Gate: if 0b or 0c fails, the design changes before a line of app code is written. This is the whole point of the phase.

**Phase 1, scaffold.** Xcode project, bundle ID, Developer ID signing from the first commit so TCC grants survive rebuilds, `LSUIElement` accessory app, test target, `~/Library/Application Support/utter/`.

**Phase 2, permission onboarding.** The three grants, a first-run flow, a permission state model, and a menu bar item that names the missing grant. Nothing else works without this, so it lands before anything that depends on it.

**Phase 3, audio capture.** `AVAudioEngine`, 16 kHz mono Float32, ring buffer, hold-to-record, release-to-transcribe. Declare batch-on-release. No VAD.

**Phase 4, transcription.** FluidAudio `AsrManager` plus Parakeet v2. Model presence check, download through FluidAudio's `ModelHub`, explicit model-missing error state.

**Phase 5, insertion.** Clipboard plus Cmd+V with pasteboard save and restore, a per-bundle-ID routing table, and a real success predicate. This is where the product lives or dies, so it gets its own phase and its own test matrix.

**Phase 6, the pill.** `NSPanel`, states `{hidden, recording, transcribing, inserting, failed}`. Zero text on screen stays. A failure must be visible.

**Phase 7, history and stats.** SQLite. Separate the 10-item buffer from the aggregates. Add a retention policy and an index on `timestamp`.

**Phase 8, vocabulary.** FluidAudio `CtcKeywordSpotter` plus `VocabularyRescorer`. Delete the "prompt hints" line from Section 5.

**Phase 9, Mode 2.** OpenAI-compatible client with a timeout, fallback to raw on any failure, Keychain for credentials, an explicit indicator that text leaves the machine, and both raw and refined saved to history.

**Phase 10, packaging.** Notarized DMG or Homebrew cask, attribution surface for CC-BY-4.0 weights, README, license.

## The two decisions that matter most

**Text insertion.**

| Option | Works in | Cost | Verdict |
|---|---|---|---|
| Clipboard + synthesized Cmd+V | Effectively everything, including browsers, Electron, terminals | Mutates the clipboard, needs save and restore, needs a paste delay | Ship this. Handy does. |
| `AXUIElement` value write | Some native Cocoa fields only | Destroys field content, selection, and undo | Not viable as the primary |
| `CGEvent` Unicode typing | Most apps, except Secure Event Input | Slow for long text, blocked in password fields | Keep as a secondary path |

Recommendation: clipboard paste as primary, `CGEvent` typing as secondary, per-bundle-ID routing table, and a visible failure state. Drop AX from the primary path.

**STT runtime.**

| Option | Cost | Verdict |
|---|---|---|
| Adopt FluidAudio | Apache-2.0, inherits its release cadence | Do this. It already ships the decode loop, VAD, `ModelHub`, and the vocabulary rescorer. Rewrites G3 and G4 into a dependency. |
| Write the decode loop | Weeks of work, and FluidAudio's own history shows a multi-round bug hunt in the vocabulary path alone | Not compatible with "minimal" |

Adopting FluidAudio deletes most of Sections 5, 6, and 7, which is the point. ADR 001 and ADR 002 stay sound. The vocabulary mechanism changes from prompt hints to CTC keyword spotting.

## What holds up

Worth saying plainly, because these are the decisions that make the project worth building.

- **ADR 002, reject the embedded LLM runtime.** Correct. An OpenAI-compatible client is the right seam, keeps the binary small, and makes local Ollama and remote proxies interchangeable. FluidVoice does the same thing. The defect is the missing contract around it, not the decision.
- **ADR 003, lean local SQLite stats with no telemetry.** Right storage choice, right posture for the network dimension.
- **ADR 004, the rolling safety buffer.** The strongest decision in the document. Given the insertion risks, the buffer is not optional, it is the primary mitigation for silent data loss. Only its execution is wrong (G5, G10).
- **ADR 001, reject the in-app model catalog.** Right motivation, wrong interface (G6).
- **CoreML on the Neural Engine.** Validated. The models exist, the export is maintained, the licenses are permissive, and this is the only way to reach Handy and FluidVoice-class latency without a GPU.
- **Push-to-talk against a batch model.** Well matched. Release is a clean utterance boundary, so no streaming architecture is needed. This also means VAD should come out.
- **Zero text rendering on screen.** A defensible, opinionated call that matches how these tools are used. It only becomes a bug in combination with silent failure.

## If you do three things

1. **Adopt FluidAudio.** It deletes the decode loop, the VAD question, the model downloader, and the broken vocabulary mechanism. Rewrites G3, G4, and half of G6 as a dependency.
2. **Run the Phase 0 spike before writing any app code.** The insertion matrix and the TCC survival test decide the design. An afternoon of throwaway code retires G1, G2, and G12.
3. **Decide the signing story now.** It constrains bundle ID, update mechanism, and every contributor's workflow, and it is not cheaply reversible.
