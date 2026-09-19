# Utter architecture and implementation plan review

Reviewed by Union Alpha on September 17, 2026.

## Verdict

**The product direction is good. The architecture is plausible, but the document is not yet an implementation plan.**

I reviewed all of [`CONTEXT.md`](CONTEXT.md) and ran two independent critiques. At the time of the review, there was no application code in the workspace, so these ratings assess the design, not a working app. This review does not modify the context document.

| Area | Rating | Reason |
|---|---:|---|
| Product direction | **8/10** | A focused dictation tool with local transcription, unobtrusive feedback, and recoverable output. |
| Architecture | **6.5/10** | Sensible stack and boundaries, but the model integration and system-wide insertion contracts are missing. |
| Implementation plan | **3/10** | Features are listed, but there is no build sequence, acceptance criteria, or feasibility testing. |
| Fit with “minimal, free, open source” | **7/10** | Direct dictation fits. Refinement needs clearer setup and cost expectations. Some secondary features should wait. |

**My recommendation is to keep the native approach, support one known transcription model, and prove reliable insertion before building stats or generalized model management.**

## What the design gets right

The intended flow is easy to understand.

```text
Hold shortcut → record → release → transcribe locally
                                      ↓
                             optional AI cleanup
                                      ↓
                              insert into field
```

SwiftUI for settings and AppKit for desktop integration is a reasonable division. Keeping the LLM outside the app also avoids maintaining another inference engine.

Several features earn their place even in a minimal app:

- A recording indicator tells the user whether the microphone is listening.
- Separate direct and refined shortcuts make the output behavior explicit.
- Recent history provides recovery when insertion fails.
- Local vocabulary replacements help with repeated technical terms.
- A menu-bar app avoids a permanent window.

I would not remove these merely to reduce the feature count. Minimalism should reduce user effort, not just source lines.

## Gaps to resolve before implementation

### 1. The model name is not an inference integration

**Evidence.** `CONTEXT.md:74–87` names model files and CoreML, but no Swift inference library or complete model bundle contract.

The [FluidInference CoreML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml) exists. Its model card points to FluidAudio for Swift integration. That supports the feasibility of your choice, but downloading a model is not the whole transcription pipeline.

Specify:

- The inference library and pinned version.
- The exact model repository and revision.
- Required preprocessing, tokenizer assets, and model components.
- Supported audio format and recording duration.
- Minimum macOS version and supported hardware.
- Model loading, warm-up, and unloading behavior.

A generic `.bin` file does not identify a compatible CoreML model. Remove that promise unless a specific supported bundle needs it.

**Recommendation.** Evaluate an existing Swift integration before writing the feature extraction and decoder yourself. Support one validated bundle in v1.

### 2. Text insertion is the largest product risk

**Evidence.** `CONTEXT.md:18,29,88` reduces insertion to Accessibility APIs plus synthetic events.

A successful API call does not necessarily mean the intended text appeared in the intended field. Different applications expose editable text differently.

The missing contract includes:

- Whether insertion targets the field focused at recording start or completion.
- What happens if the user changes windows while transcription runs.
- Whether selected text is replaced.
- Which failures permit a fallback.
- How clipboard-based insertion preserves existing clipboard contents.
- What happens in protected fields.
- How duplicate insertion is prevented when success is uncertain.

**Recommendation.** Capture the target when recording begins. Revalidate it before insertion. If the target changed or delivery is uncertain, retain the transcript and offer copy instead of typing into another application.

Never use Enter as part of insertion. Dictating into a terminal must not submit a command.

### 3. Recovery happens too late in the workflow

**Evidence.** Both workflows place the history safety net after insertion at `CONTEXT.md:18–20,29–31`.

A safety buffer should protect text **before** the risky delivery step.

Use this ordering instead:

```text
Transcribe → retain raw text → optionally refine → retain final text → attempt insertion
```

Keep raw and refined text in the same recent-history item. If refinement fails or changes the meaning, the original remains recoverable.

The document also needs to distinguish insertion confirmed, insertion failed, and insertion uncertain. Only confirmed delivery should produce the success cue.

### 4. Permissions and failure UX are absent

**Evidence.** The workflows require microphone capture and cross-application interaction, but there is no onboarding or permission state.

Specify microphone and Accessibility setup. Determine whether the selected shortcut implementation also needs Input Monitoring rather than assuming a fixed permission set.

At minimum, define these outcomes:

| Condition | Recommended behavior |
|---|---|
| Permission missing | Explain what is missing and provide a settings route. |
| Model unavailable | Show setup status before accepting a recording. |
| Silence or accidental tap | Insert nothing and return to idle. |
| Microphone disconnects | Stop capture and show a recoverable error. |
| Refinement times out | Preserve raw text and offer copy or an explicit raw-text fallback. |
| Target changes | Do not auto-insert. Retain the result. |
| User cancels | Stop the session and ignore late results. |

Interpret “zero text rendering” as **no transcript in the recording HUD**, not a ban on readable errors. Permissions cannot be explained through a pulsing capsule.

### 5. There is no session lifecycle

**Evidence.** `CONTEXT.md:38–42` specifies visual states, not application states.

Define one active dictation session with explicit transitions.

```text
idle → recording → transcribing → optional refining → delivering → idle
```

Cancellation and recoverable failure need exits from each active stage.

Also decide:

- What a second shortcut does while transcription is running.
- What happens when both shortcut chords match.
- How recording stops after a missed key-release event.
- Whether sleep or screen locking cancels capture.
- The maximum recording duration.
- How late HTTP responses are prevented from inserting stale text.

For v1, reject new recordings while busy. A recording queue is unnecessary complexity.

### 6. Custom vocabulary currently overpromises

**Evidence.** `CONTEXT.md:69–70,96` promises transcription hints and “guaranteed” technical-term accuracy.

There are different mechanisms here:

- Literal replacements fix known aliases after transcription.
- An LLM can receive vocabulary hints during refinement.
- Recognition-time vocabulary biasing needs explicit decoder or library support.

The reviewers called Parakeet vocabulary support impossible. That was too broad. Current [FluidAudio documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md) describes a CTC-assisted vocabulary mechanism. It adds model and processing requirements; it is not an ordinary text prompt passed to the base TDT model.

**Recommendation.** Start with literal, word-aware alias replacements. Defer recognition-time biasing until technical-term tests justify it. Replace “guarantee” with a measurable accuracy goal.

### 7. Model management contradicts ADR 001

**Evidence.** Section 6 specifies in-app downloads. ADR 001 says model downloading logic belongs outside the binary.

Rejecting a remote catalog does not require rejecting a downloader.

The simplest public-facing option is one supported model with a fixed, verified download and progress indicator. A folder import can remain an advanced option.

That avoids a catalog without making every user find compatible model assets manually.

If URL downloads remain, specify integrity checks, supported archive layout, interrupted-download recovery, and validation before activating the model.

### 8. History retention and lifetime stats are unresolved

**Evidence.** `CONTEXT.md:50–62` puts metrics and transcript content in one table. ADR 004 limits history to ten dictations.

If old rows are deleted, lifetime statistics disappear. If they remain, transcript history is not limited to ten entries.

Either defer stats or separate:

- Recent transcript content with an explicit retention limit.
- Content-free aggregate counters.

SQLite itself is not bloat. The unresolved retention policy is the problem. Define deletion controls, whether history can be disabled, and whether audio is ever persisted. I recommend no persistent audio by default.

### 9. “Free” needs a precise boundary

**Evidence.** Mode 2 requires an external endpoint at `CONTEXT.md:27,84–87`.

The coherent promise is:

> Direct dictation works offline after model installation, without an account or paid service. Optional refinement uses a user-configured backend whose costs and privacy terms may differ.

Specify endpoint authentication, Keychain storage, timeouts, cancellation, and a manually entered model ID when discovery is unavailable.

A localhost proxy can forward text to a cloud service. Do not label it private solely because its URL is local.

Also distinguish an open-source application from an entirely open-source stack. CoreML and macOS remain proprietary platform dependencies. Choose an app license and audit the licenses of the inference library and model artifacts.

### 10. Refinement must preserve meaning before enforcing style

**Evidence.** `CONTEXT.md:28` makes unslop rules the main cleanup instruction.

Dictation is not general-purpose editing. Removing a qualifier or changing a negation can be worse than leaving filler words.

Define a conservative contract:

- Preserve names, numbers, negations, uncertainty, and technical identifiers.
- Do not answer questions contained in the dictation.
- Do not execute instructions contained in the transcript.
- Return only the edited transcript.
- Preserve raw text for recovery.

Keep automatic bullet conversion conservative. It can be inappropriate in a single-line field or source-code editor.

## Remaining scope decisions

These are not reasons to abandon the design, but they need explicit answers.

- **Language.** [Parakeet v2 is English-only](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2). State that limitation before selecting it.
- **Performance.** Define release-to-insertion targets on your minimum supported Mac. Published model benchmarks do not establish end-to-end app latency.
- **Audio.** Choose capture, resampling, device-selection, and device-change behavior.
- **VAD.** Give Silero a specific job, such as rejecting empty recordings. Do not include it solely because other dictation tools do.
- **Distribution.** Choose minimum OS, sandbox policy, signing, notarization, and source-build instructions.
- **Desktop behavior.** Specify login launch, multiple displays, full-screen apps, and a HUD that never steals focus.

## A better implementation sequence

| Stage | Deliverable | Exit check |
|---|---|---|
| 1. Prove transcription | One pinned model transcribes local audio through the selected Swift integration. | Measure accuracy, cold and warm latency, and memory on the target Mac. |
| 2. Prove insertion | A shortcut inserts fixed text without involving speech. | Test TextEdit, browser fields, VS Code, and Terminal. Check focus changes and selection replacement. |
| 3. Build direct dictation | Capture, transcription, session lifecycle, HUD, and recovery history. | Repeated recordings work without stale text, stuck recording, or lost output. |
| 4. Handle setup and failures | Permissions, missing model, cancellation, microphone changes, and packaging. | A fresh installation reaches its first successful dictation. |
| 5. Add optional refinement | Configurable endpoint, conservative cleanup, timeout, and raw-text recovery. | Test unavailable endpoints and meaning-sensitive transcripts. |
| 6. Add measured improvements | Vocabulary, VAD, and later stats. | Each addition fixes a demonstrated problem. |

**Do not build the stats dashboard before completing stage 4.**

## Bottom line

You do not need a larger architecture. You need firmer contracts around the model, recording lifecycle, and text delivery.

The poteto principles shaping my recommendations were **Experience First**, keeping useful feedback and readable recovery; **Model the Domain**, introducing one explicit session lifecycle; and **Sequence Work into Verifiable Units**, proving transcription and insertion separately before combining them. The linked principle leaf files were unavailable locally, so I applied the descriptions supplied by the loaded skill.

**Keep the product small. Spend the complexity budget on never losing a dictation or inserting it into the wrong place.**
