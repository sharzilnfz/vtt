# Utter unified plan

## What this document is

One readable summary of every research document in this repo. It states what the app is, how it will work, which decisions are settled, which trade-offs each decision carries, and which questions still need evidence before you build. No code exists yet, and this document does not change any other file.

## The app in one paragraph

You hold a key, talk, and let go. The app records your voice, turns it into text on your Mac with no network call, saves the raw text to a small safety buffer, then pastes the text into whatever field you were just typing in. Hold a second key instead and the app also sends the raw text to an AI endpoint that cleans it up first, and falls back to the raw text if that request fails. A small pill at the bottom of the screen shows what is happening. No transcript is ever drawn on screen.

## The three goals, in priority order

1. Never lose a dictation. Every transcript lands in a safety buffer before anything risky happens.
2. Never paste into the wrong place. The app remembers which app and field you were in when you started, and aborts if that changed.
3. Be the lightest app on the machine. Idle cost, resident memory, and energy per dictation matter more than features.

## How one dictation flows

1. You press and hold the shortcut. The app records which app and window is active, and starts capturing audio.
2. While you talk, the pill shows a live input level.
3. You release. Capture stops and the audio goes to the transcription engine, which runs entirely on your Mac.
4. The raw transcript is saved to the safety buffer immediately, before any network call or clipboard work.
5. Mode 1 inserts now. Mode 2 first sends the raw text to your configured AI endpoint with a five second timeout. If that fails for any reason, the raw text is what gets inserted.
6. The app checks that you are still in the same app as when you started. If not, insertion aborts and the text waits in the buffer.
7. Text is typed directly into the field with synthetic key events. The clipboard is never touched. A clipboard paste path stays as a fallback for long text or apps where typing fails.
8. If delivery clearly succeeded, the pill plays a soft pop. An uncertain result never plays it.

## Where your data lives

Everything sits under `~/Library/Application Support/utter/`. Two SQLite tables keep your words out of permanent storage. A rolling ten item buffer holds recent raw and refined transcripts so you can re-insert them after a failed delivery. A second table holds content free counters, words per day and seconds per mode, with no text at all. Custom vocabulary aliases live in a JSON file. Audio is never written to disk.

## Audio, one place where the spec changes

The spec says Float32. The measured fork uses Int16, which halves the buffer bytes and is the format the model wants, with no accuracy cost. The plan adopts Int16. Microphone input gets converted once from whatever the device supplies, at a cheaper resampler quality than the fork's maximum setting, since the model was trained on degraded speech anyway. Recording stays in memory, not on disk. A level meter reuses the capture buffers instead of running a second pipeline.

## The state machine

One dictation session can be alive at a time. The pill mirrors it.

- `idle`, hidden
- `recording`, expanding pill with input level
- `transcribing`, compact shimmer
- `refining`, pulsing while the AI request is in flight
- `failed`, brief red indicator for microphone or network trouble
- `inserting`, the moment text is typed in

If you press the shortcut again while busy, the request is rejected rather than queued. A missed key release stops recording after a cap. Sleep and screen lock cancel the session. Pressing the re-insert shortcut runs a short session of its own. It goes from `idle` to `inserting` and back, with no recording step.

## Clipboard-free insert and re-insert last

Two additions. Both use the same typing path. Neither touches the clipboard.

**Feature A: clipboard-free insert.** Dictation is typed into the field with synthetic key events instead of clipboard paste. History saving does not change. The raw text still lands in the safety buffer before insertion. The clipboard keeps whatever you copied before.

**Feature B: re-insert last.** A separate shortcut types the most recent buffer entry again at the current cursor. It performs no recording and no network call. It replays the final text of the last session. That means the refined text when Mode 2 refined it, else the raw text. It creates no new history entry. If the buffer is empty, the pill shows `failed` briefly and nothing is typed.

How to use them. Hold Right Option, talk, and release. The words appear where you type. Move to another field later and press Option+V. The same words appear there. Open settings to change either shortcut.

The insertion engine owns two paths. Typing is the default. Clipboard paste with guarded restore stays as the fallback for long text or apps where typing fails. A small per-app routing table records which path each app needs. The history store owns the ten item buffer. The shortcut manager owns the new hotkey.

Why typing instead of the accessibility API. The accessibility API has no insert-at-cursor action and fails in browsers, Electron apps, and terminals. Key event typing works in nearly every app. That finding already appears in the first review, so this choice reuses it rather than relitigating it.

Terminal protection stays. A trailing newline in a terminal can run a command. The engine strips a trailing newline or asks first, and it never emits Enter on its own.

Password fields stay out. Synthetic key events are blocked in secure input. The engine aborts there and keeps the text in the buffer.

## What is settled

These decisions appear in more than one research document and do not conflict.

- FluidAudio for on-device inference, Apache-2.0. It ships the decode loop, model download, and vocabulary rescoring you would otherwise write.
- Clipboard-free typing as the default insertion path. Clipboard paste with guarded restore stays as the fallback. Accessibility APIs cannot insert at the cursor, and browsers, Electron apps, and terminals do not expose editable text to them.
- Raw transcript saved before anything risky.
- Rolling buffer and aggregates in separate tables, no permanent plaintext.
- OpenAI-compatible HTTP endpoint for refinement, no embedded LLM. Raw text fallback on any failure.
- One session at a time.
- macOS standard paths, `LSUIElement` menu bar app, no telemetry.
- AppKit for the pill and system hooks, SwiftUI only where it is cheap, settings included.
- Configurable shortcuts that avoid the VoiceOver Control+Option collision. Defaults: Right Option for direct, Option+Command for refined, Option+V for re-insert last. Control+V is not used because it would hijack paste in every app.

## What the research disagrees on, and my recommendation

**The starting app.** `FOUNDATIONS.md` says fork OpenSuperWhisper, 68 files, MIT, already on FluidAudio. The efficiency research says start from a reduced MiniWhisper fork instead, because the priority shifted to runtime cost. Both are MIT, both sit on FluidAudio, and the disagreement is about which feature set gets deleted versus kept. My take is to benchmark both baseline builds in Phase 0 with the measurement script, then pick. The cost of testing both is one afternoon.

**The model.** Parakeet v2 at 0.6B parameters is the accuracy baseline, roughly 2.6 percent word error on clean speech, but it holds somewhere between 477 MB and 1212 MB resident. The 110M hybrid holds about 227 MB at 3.01 percent word error. The efficiency document argues the accuracy loss is invisible in dictation and the memory saving is permanent. The caveat is that the two throughput numbers come from different machines, so speed on your M1 is unknown. My take is to ship 110M as the default, keep 0.6B as an opt-in quality tier, and verify accuracy on your own voice before locking it in. Never use the int4 encoder, FluidAudio's own benchmark shows it is slower and worse.

**Memory policy.** Keep the model warm by default so there is no stall after key release. Add a memory pressure valve that drops the model under system pressure and rebuilds it lazily. FluidAudio exposes no unload API, so the valve works by dropping the manager reference. The efficiency research prefers a short warm cache with a measured timeout. The deciding factor is your 8 GB machine. My take is warm by default plus the pressure valve first, and a warm cache timeout only if resident memory measures above the target.

**Language scope.** Parakeet v2 is English only. v3 is multilingual but heavier. State the limitation in the README rather than solving it now.

**Updater.** Sparkle adds idle cost for an update experience a personal tool does not need. Skip it, update by hand.

## Trade-offs you are accepting

Every choice here buys something with something else. These are the ones worth knowing before you commit.

| Decision | What you gain | What it costs |
|---|---|---|
| Clipboard paste as fallback | Fast for long text where typing would crawl | Mutates the user clipboard for a moment, needs a guarded restore, and there is no certain confirmation the text landed |
| On-device transcription | Private, offline, no per-use cost | Model sits in RAM all day, English only, and long recordings pay a chunking overhead past 15 seconds |
| 110M model default | Roughly 570 MB less resident memory | About 0.4 points more word error on clean speech, small for dictation |
| Warm model by default | No stall when you release the key | Memory held while you work on other things |
| No text on screen | Small pill, zero distraction | Every failure must be communicated by color or icon, so failures need careful design |
| No embedded LLM | Small binary, any provider works | Refinement depends on an external endpoint, which has its own cost and privacy terms |
| Modifier-only push to talk | No registerable hotkey conflicts | Needs the Input Monitoring permission and an event tap the OS can disable under load |
| Literal alias replacement for vocabulary | Deterministic, works offline, no model cost | Cannot fix words the engine misheard in the first place |
| Mode 2 refinement | Cleaner text, structured bullets | Your words leave the machine, so the endpoint's privacy terms become yours |
| Clipboard-free typing as default | Your clipboard is never touched or clobbered | Slower than paste for long text, and blocked in password fields |
| Re-insert last on Option+V | One keystroke recovers text after a failed delivery | Replays text only, so it cannot fix a bad transcription on its own |

## Open decisions that need evidence, not opinion

Ordered by how much they can hurt.

1. **Does typing actually land in your apps.** TextEdit, VS Code, Chrome, Slack, Terminal, Notes. The typing path is the plan's foundation, so it is tested first with throwaway code. Clipboard paste is tested alongside as the fallback.
2. **Do permissions survive rebuilds.** macOS ties permission grants to the app's code signature. Without a stable signing identity, every rebuild drops Microphone, Accessibility, and Input Monitoring grants. Decide the signing and distribution story before writing app code, since it also fixes the bundle ID.
3. **Which engine is fastest on your Mac.** Parakeet 110M versus 0.6B versus Apple Speech versus whisper.cpp, measured on your M1 with `scripts/measure-efficiency.sh`. Thresholds get written down before the runs, not after.
4. **Warm forever or warm cache.** Measure resident memory with the model warm on your 8 GB machine. Add a timeout only if the number is above target.
5. **Maximum recording length.** The encoder takes at most 15 seconds per pass, and longer audio gets chunked with about 13 percent redundant compute. Decide whether long holds are truncated, chunked, or rejected.
6. **Does the refinement prompt preserve meaning.** Style cleanup must not drop negations, names, or numbers, and must never execute instructions contained in the dictation.
7. **How fast is typing for long dictations.** Measure characters per second through synthetic key events on your Mac. Set the length where the engine switches to clipboard fallback.
8. **Does Option+V collide.** Confirm the re-insert shortcut does not fight an app you use daily. Keep it configurable regardless.

## Build order

Each phase ends with a check before the next starts. The numbers below are the proposed acceptance targets from the efficiency research. They are design goals, not measurements, and they get tightened once a baseline exists.

| Metric | Target |
|---|---|
| Resident memory, 110M model warm | under 300 MB |
| Resident memory, 0.6B model warm | under 900 MB |
| Idle CPU | under 0.1 percent, zero timer wakeups |
| Release to inserted text, 5 second utterance | under 400 ms |
| Binary and frameworks, models excluded | under 25 MB |

## Stages

| Stage | Deliverable | Exit check |
|---|---|---|
| 0 | Throwaway spikes: transcription works on this Mac, typing lands in six apps, hotkey tap fires, both fork baselines measured | Insertion matrix passes and permissions survive a rebuild |
| 1 | Scaffold, signing, menu bar app, permission flow | A fresh install reaches the first successful dictation |
| 2 | Audio capture and direct dictation end to end | Repeated recordings, no stale text, no lost output |
| 3 | Insertion engine with target revalidation, typing default plus clipboard fallback, and re-insert last | Wrong-target insert is impossible, clipboard is untouched on the default path, Option+V replays the last entry |
| 4 | The pill and its states | Every failure is visible without text |
| 5 | Optional refinement client | Unavailable endpoint falls back to raw text, meaning preserved |
| 6 | Safety buffer, stats, vocabulary aliases | Each addition fixes a demonstrated problem |

## What still has no answer

Target app capture and revalidation is not in any existing fork. The attribution surface for the CC-BY-4.0 Parakeet weights needs a home in the UI. No first run onboarding exists in any candidate. Energy per dictation has no published number for any engine, so it has to be measured here.
