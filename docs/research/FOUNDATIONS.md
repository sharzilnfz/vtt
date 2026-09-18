# Build versus fork: what to reuse

Reviewed `CONTEXT.md` as updated, plus the existing `REVIEW.md` and `REVIEW-union-alpha.md`. The question is whether to build the app from nothing or stand on an existing open source project.

## Answer

Yes, reuse. At three separate layers, and only one of them means forking an app.

| Layer | Reuse it? | What you get |
|---|---|---|
| Library | Already decided | FluidAudio for CoreML inference. Keep this. |
| App | Fork one, and only one | OpenSuperWhisper, MIT, Swift, already on FluidAudio. Roughly 60 percent of your spec exists there. |
| Reference | Read, never depend | Handy for insertion edge cases. VoiceInk for the refinement boundary and modifier-only fixes. FluidVoice for the panel work. |

Do not fork a GPL project unless you intend your app to be GPL. That single constraint removes the two most complete candidates from the fork list.

## The candidate landscape

Verified through the GitHub API on 2026-09-17.

| Project | License | Stack | Code size | Stars | Last push |
|---|---|---|---|---|---|
| Handy | MIT | Rust plus TypeScript, Tauri | 62 Rust, 154 TS | 31,814 | 2026-09-15 |
| FluidVoice | GPL-3.0 | Swift | 209 files, 4.45 MB | 11,604 | 2026-09-17 |
| VoiceInk | GPL-3.0 | Swift | 367 files, 2.58 MB | 6,438 | 2026-09-17 |
| OpenSuperWhisper | MIT | Swift | 68 files, 638 KB | 2,893 | 2026-09-15 |
| FluidAudio | Apache-2.0 | Swift SDK | not an app | 2,770 | 2026-09-14 |

All five are actively maintained. None is archived.

Handy is the largest project by a wide margin and the only permissive cross-platform one, but it is Tauri and Rust, and it runs Parakeet through `transcribe-rs` rather than CoreML on the Neural Engine. Forking it means abandoning the native Swift decision your spec now records in Section 6.

## Why OpenSuperWhisper is the right fork target

Three things make it the only candidate that fits.

**It is already on your stack.** Its `Package.resolved` pins `fluidaudio 0.15.6`, `grdb.swift 7.11.1`, and `keyboardshortcuts 3.0.1`. FluidAudio for Parakeet, GRDB for SQLite, and Sindre Sorhus's shortcut library are the exact three dependencies your spec would have chosen. The STT layer is already wired.

**It is small enough to actually own.** 68 Swift files, 638 KB. FluidVoice is 7 times larger and VoiceInk is 4 times larger. A fork you cannot read is a fork you cannot maintain.

**Its modules map onto your sections one to one.**

| Your spec section | Their file | Size |
|---|---|---|
| Section 2, audio capture at 16 kHz | `AudioRecorder.swift`, `PCMRecording.swift` | 16.2 KB, 7.4 KB |
| Section 2, push-to-talk on a modifier | `ShortcutManager.swift` plus `ModifierKeyMonitor` | 7.6 KB |
| Section 4, clipboard insertion engine | `Utils/ClipboardUtil.swift` | 10.4 KB |
| Section 3, the floating pill | `Indicator/IndicatorWindow.swift`, `IndicatorWindowManager.swift` | 21.9 KB, 12.9 KB |
| ADR 006, re-entrancy lock | `RecordingSessionController.swift` | 869 bytes |
| Phase 1, TCC permissions | `PermissionsManager.swift` | 8.2 KB |
| Section 5, history storage | `Models/Recording.swift` plus GRDB | 21.5 KB |
| Onboarding gap from my review | `Onboarding/` | present |
| Engine seam | `Engines/TranscriptionEngine.swift` | 349 bytes, a protocol |

`RecordingSessionController` is 869 bytes and does exactly what ADR 006 asks. `begin` returns `nil` when a session is already live, so a second recording request is rejected rather than queued. That is your re-entrancy lock, already written and already covered by `RecordingSessionTests`.

## Two things the fork does better than your spec

This is the part worth reading twice. Their `ClipboardUtil` contains two corrections to Section 4 as written.

**Their clipboard restore is guarded, yours is not.** Your spec says restore the original pasteboard contents. Theirs restores only if the pasteboard still holds the transcribed text, checked against the `changeCount` captured at copy time. The reason is in the code comment. If the user copies something else during the 1.5 second window, an unconditional restore destroys their data. Your spec as written has that bug.

**Your Cmd+V keycode is wrong on non-QWERTY layouts.** Your spec says emit synthesized Cmd+V key events. Keycode 9 is V on QWERTY and is a different character on Dvorak, Dvorak Left and Right Hand, and every non-Latin layout such as Russian. Their code walks the active layout with `UCKeyTranslate` to find the keycode that actually produces "v", special-cases the "Dvorak - QWERTY Command" family, and falls back to keycode 9 when the layout has no Latin mapping. On a Russian layout your spec sends the wrong key and pastes nothing.

Both are fixed by taking their file. Neither is obvious, and I did not catch either one in the first review.

## What the fork does not give you

Be clear-eyed about the remaining work. I grepped their `TranscriptionService` and `ShortcutManager` for target-app handling and found nothing.

- **Target capture and revalidation.** Section 4 requires capturing the target window and bundle ID at recording start and aborting if the active app changed. OpenSuperWhisper has no `frontmostApplication` or `bundleIdentifier` logic at all. You build this.
- **The two-mode design.** They have one recording path. Your Mode 1 and Mode 2 with different chords, different retention, and an optional refinement step is new.
- **The refinement client.** Their AI layer is not an OpenAI-compatible HTTP client with a 5-second timeout and raw-text fallback. VoiceInk has something closer in `VoiceInkRefineXPC`, so read that one.
- **Vocabulary aliases.** Their custom dictionary is an open TODO, issue #19. VoiceInk has a working dictionary with JSON import and export.
- **Aggregates-only stats.** They store recordings, not content-free counters. Your ADR 004 is stricter than their model.
- **No transcript on screen.** They display transcriptions. Your Section 3 constraint is the opposite, so their recording list UI comes out.
- **Parakeet only.** Their Whisper path is 12 files in `Whis/`. You want it gone.

## The deletion list

A fork is mostly a deletion exercise. From OpenSuperWhisper, cut the Whisper engine and its 12 files, `TranscriptionQueue`, the drag-and-drop file transcription, the recording list UI, multi-language and auto-detect, the Asian and Hebrew autocorrect bridge, and the model manager's Whisper catalog. Keep the four hard modules and the test files that cover them. Expect their test suite to fail loudly as you cut, which is a feature, because it tells you what you broke.

## Licensing

| License | Projects | What it means for you |
|---|---|---|
| MIT | OpenSuperWhisper, Handy | Take the code, ship under anything, keep the notice. |
| Apache-2.0 | FluidAudio | Same, plus a patent grant. Keep the notice. |
| GPL-3.0 | FluidVoice, VoiceInk | Your app becomes GPL-3.0. You must publish source and cannot relicense later. |
| CC-BY-4.0 | Parakeet weights | Attribution required in the app. Still an open gap from my first review. |

FluidVoice was Apache-2.0 before 2026-02-23. The relicensing commit is `docs: relicense project to GPLv3 with effective date`, and the README confirms versions published before that date were Apache-2.0. So the last pre-relicensing commit is a permissive fork target, roughly seven months behind upstream and missing the Parakeet rebuild, the onboarding work, and the theming. Worth knowing, but OpenSuperWhisper is the better permissive base because it is smaller and already minimal.

Confirm that reading with a lawyer before you rely on it. I am reporting what the repository states, not giving legal advice.

## Recommended path

1. **Fork OpenSuperWhisper at a pinned commit.** Not a tracking fork. You are taking a snapshot, not maintaining a downstream.
2. **Spike first, using their code as the test harness.** Their `ClipboardUtil` takes an injectable `postEvent` closure, which is why they can test it. Run Spike 0b from your Phase 0 against their implementation rather than writing your own, and confirm it lands text in TextEdit, VS Code, Chrome, Slack, and Terminal.
3. **Delete before you add.** Cut the Whisper path, the queue, the file transcription, and the recording list UI first. Get to the minimum before writing anything new. A fork you add to before subtracting from becomes their app with your features bolted on.
4. **Build the four missing pieces.** Target revalidation, the two-mode state machine, the refinement client with fallback, and content-free aggregates.
5. **Keep their test files for the modules you keep.** `RecordingSessionTests`, `TranscriptionCancellationTests`, `TriggerPermissionTests`, and `PCMRecordingTests` cover the exact failure classes your spec worries about.
6. **Read Handy for the insertion edge cases and VoiceInk for the refinement boundary.** Read, do not depend.

## What this saves

The honest accounting. Their four hard modules total roughly 43 KB of Swift across clipboard insertion, modifier-only hotkey capture, audio capture, and permissions, plus 20 test files, plus a notarization script and a model download story. That is the fiddly half of the app, and the half where the bugs live. You still write the mode logic, the target revalidation, the refinement client, and the stats. Call it 60 percent reuse of the components and 0 percent reuse of the product decisions, which is the right split, because the product decisions are yours.

## Principles applied

**Laziness protocol** shaped the recommendation itself, biasing toward taking working code over writing new code for the fiddly parts. **Subtract before you add** produced the deletion list as step 3, before any new code. **Build the lever** is why the recommendation is a pinned snapshot rather than a tracking fork, since a fork you keep merging from is a lever that keeps charging you. **Prove it works** is why Spike 0b runs against their implementation instead of a fresh one, so the first real evidence is about the actual artifact. **Fix root causes** is why the layout-aware keycode and the `changeCount` guard matter, since both are symptom-free in testing and produce silent wrong output in production. **Exhaust the design space** is why I compared five projects on license, stack, and size rather than defaulting to the most popular one, which would have been Handy and the wrong stack.
