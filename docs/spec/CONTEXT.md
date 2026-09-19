# Project Context: Utter (Minimal Voice-to-Text with AI Enhancement)

## 1. Vision

A minimal, fast, native macOS voice-to-text dictation tool.
It uses native CoreML for local transcription on Apple Silicon via FluidAudio.
It formats and cleans speech using an OpenAI-compatible CLI proxy or local engine.
It eliminates closed-source runtimes, background telemetry, and complex model stores.

## 2. Core Workflows

### Mode 1: Direct Dictation
- **Keybind:** Push-to-talk hold on configurable shortcut (default: `Right Option` or non-colliding chord; avoids VoiceOver `Control + Option` collision).
- **Action:** Microphone captures audio while held via `AVAudioEngine` (16 kHz mono Float32).
- **Audio Cue:** Subtle system click on key press.
- **Release:** Audio buffer passed to FluidAudio running `parakeet-tdt-0.6b-v2-coreml`.
- **Retention:** Raw transcript is immediately saved to the rolling 10-item safety buffer before insertion.
- **Vocabulary:** Post-transcription alias replacement table corrects technical terms and acronyms.
- **Insertion:** Text is injected via clipboard save, pasteboard copy, synthesized `Cmd+V`, and pasteboard restoration.
- **Completion Cue:** Soft pop sound upon confirmed delivery.

### Mode 2: AI Refined Dictation
- **Keybind:** Push-to-talk hold on secondary shortcut (default: `Option + Command`).
- **Action:** Microphone captures audio while held.
- **Audio Cue:** Subtle system click on key press.
- **Release:** Audio buffer passed to FluidAudio for raw transcription.
- **Retention:** Raw transcript is immediately saved to the safety buffer.
- **Processing:** Raw text is sent to an OpenAI-compatible HTTP endpoint (CLI proxy) with a 5-second timeout.
- **Fallback:** If HTTP times out, errors, or is unreachable, the raw text is preserved and inserted directly.
- **Prompt:** Enforces the unslop style rules. Removes filler words, fixes grammar, structures output as natural bullet points when appropriate.
- **Retention:** Refined transcript updates the safety buffer entry.
- **Insertion:** Refined text is injected via clipboard paste.
- **Completion Cue:** Soft pop sound upon confirmed delivery.

## 3. UI and Visual Feedback

- **Component:** Floating non-activating pill panel at bottom-center of the active display.
- **Window Attributes:** `NSPanel`, `.nonactivatingPanel`, floating above all spaces. Never steals key focus from active editor.
- **Visuals:** Audio waveform activity while speaking.
- **States:**
  - `idle`: Hidden.
  - `recording`: Expands smoothly and displays audio input level.
  - `transcribing`: Shows compact processing shimmer.
  - `refining`: Pulses during external HTTP request.
  - `failed`: Displays brief subtle red indicator if microphone or network fails.
  - `dismissed`: Hides upon text insertion or cancellation.
- **Constraint:** No transcript text rendered on screen. Errors are visible via icon or color.

## 4. Text Insertion Engine

- **Target App Capture:** Target window and bundle ID are captured at recording start.
- **Target Verification:** If active application changes before insertion, insertion aborts and text stays safely in the buffer.
- **Mechanism:**
  1. Save current `NSPasteboard` contents and change count.
  2. Set pasteboard string to transcribed text.
  3. Emit synthesized `Cmd+V` key events (`CGEvent`).
  4. Wait for application read cycle.
  5. Restore original pasteboard contents.
- **Terminal Protection:** Never emit `Enter` or newline triggers in terminal windows.

## 5. Storage and Paths

- **Application Directory:** `~/Library/Application Support/utter/`.
- **Model Storage:** `~/Library/Application Support/utter/models/` (or pointers to FluidAudio model store).
- **History and Stats:** SQLite database at `~/Library/Application Support/utter/history.db`.
- **Table 1 (Safety Buffer):** Rolling 10 records with `id`, `timestamp`, `raw_text`, `refined_text`, `mode`, `status`.
- **Table 2 (Daily Aggregates):** Content-free counters with `date`, `word_count`, `duration_ms`, `mode`. Text is never stored permanently.
- **Custom Vocabulary:** `~/Library/Application Support/utter/vocabulary.json`.

## 6. System Boundaries and Dependencies

- **Platform:** macOS 14.0+ (Apple Silicon).
- **Core STT Runtime:** FluidAudio (Apache-2.0 Swift package). Provides Parakeet TDT CoreML decode loop, chunking, and VAD.
- **AI Backend:** Native `URLSession` HTTP client calling an OpenAI-compatible endpoint.
- **Permissions Required:** Microphone, Accessibility. Input Monitoring if using modifier-only global taps.

## 7. Architectural Decision Records (ADRs)

- **ADR 001: Adopt FluidAudio for CoreML Inference.** Writing a custom TDT greedy decode loop and Mel feature extractor in raw Swift is error-prone. FluidAudio is Apache-2.0, runs Parakeet on Apple Silicon Neural Engine, and solves chunk stitching.
- **ADR 002: Clipboard Paste with Save/Restore as Primary Insertion.** `AXUIElement` has no insert-at-cursor API and fails in Chrome, Slack, VS Code, and Terminal. Clipboard paste plus synthesized `Cmd+V` is the universal mechanism.
- **ADR 003: Retain Raw Text Before Insertion.** Never wait until after insertion to save dictation. Transcripts must land in the safety buffer before network calls or clipboard operations to prevent data loss.
- **ADR 004: Separate Safety Buffer from Lifetime Stats.** Lifetime stats store numeric aggregates only. Persistent plaintext dictation logs are a privacy violation.
- **ADR 005: Reject Embedded LLM Runtime.** An OpenAI-compatible HTTP client handles CLI proxy, Ollama, and remote providers through a single protocol with zero binary bloat.
- **ADR 006: Explicit Session State Machine and Re-entrancy Lock.** A new recording request while transcribing or refining is rejected. No overlapping sessions.
- **ADR 007: Fallback to Raw Transcript on AI Failure.** If the CLI proxy is offline, times out, or fails, the app must never swallow the user's speech. It pastes the raw transcript.
- **ADR 008: macOS Standard Paths.** Store all app data under `~/Library/Application Support/utter/`.

## 8. Implementation Plan

- **Phase 0: Spikes (Risk-First Verification).**
  - Spike 0a: Verify FluidAudio transcribing Parakeet v2 CoreML on this Mac. Measure latency.
  - Spike 0b: Verify clipboard paste and restore across TextEdit, VS Code, Chrome, and Terminal.
  - Spike 0c: Test non-activating floating `NSPanel` pill and key event tap.
- **Phase 1: Project Scaffold and Permissions.**
  - Swift package and app setup.
  - TCC permission detection (Microphone, Accessibility).
- **Phase 2: Audio Capture and Direct Dictation.**
  - `AVAudioEngine` capture, push-to-talk lifecycle, FluidAudio integration.
- **Phase 3: Text Insertion and Target Validation.**
  - Clipboard save, paste, restore engine, window re-validation.
- **Phase 4: Floating Pill HUD.**
  - State machine visualization (`recording`, `transcribing`, `refining`, `failed`).
- **Phase 5: AI Refinement Client.**
  - OpenAI-compatible HTTP client, raw fallback, unslop system prompt.
- **Phase 6: Safety Buffer and Lean Stats.**
  - Menu bar history popover, 1-click copy, SQLite aggregates.
