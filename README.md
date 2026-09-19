# Utter

A fast, minimal, native macOS dictation application inspired by Handy and Fluid Voice. Designed for low runtime footprint on Apple Silicon (M1+), privacy-preserving local transcription via FluidAudio, and reliable system-wide text insertion.

## Core Features

- **On-Device CoreML Inference**: Uses upstream open-source `FluidAudio` for Neural Engine accelerated speech recognition (Parakeet 0.6B v2).
- **Push-to-Talk Direct Dictation (Mode 1)**: Hold hotkey (Left Ctrl + Left Option), speak, release to transcribe on-device and type directly into the focused field.
- **Push-to-Talk AI Refined Dictation (Mode 2)**: Hold secondary hotkey (Left Option + Left Command), speak, release for on-device transcription followed by style cleanup via local/OpenAI-compatible HTTP proxy.
- **Zero Clipboard Mutation by Default**: Synthetic key events (`CGEvent`) type characters directly into the active field, preserving clipboard contents. Guarded clipboard paste serves as an automated fallback for long text.
- **Safety Buffer**: Rolling 10-item buffer stores raw transcripts immediately before external network requests or insertion attempts. Text is never lost.
- **Ctrl+V Re-insert**: Replay the last dictation into any application with a single shortcut (Left Ctrl + V).
- **Target Application Validation**: Records the active window and process at start; aborts injection if the user switched apps to prevent pasting into the wrong target.
- **Floating Status Pill**: Non-activating floating `NSPanel` at the bottom-center of the screen providing live audio level feedback without stealing editor focus or drawing transcripts on screen.

## Project Structure

```text
utter/
├── Package.swift               # Swift 6 package definition (macOS 15+)
├── README.md                   # Project overview and build guide
├── Packages/
│   └── FluidAudio/             # Upstream FluidAudio CoreML engine (git submodule, pinned to 41540ea)
├── scripts/
│   └── measure-efficiency.sh  # Harness for measuring memory footprint and idle CPU
├── docs/
│   ├── spec/
│   │   └── CONTEXT.md          # Complete project specification and ADRs
│   ├── plan/
│   │   └── PLAN.md             # Unified implementation plan and build order
│   └── research/
│       ├── FOUNDATIONS.md      # Build vs. fork analysis and library landscape
│       ├── EFFICIENCY.md       # Runtime efficiency, memory levers, and metrics
│       ├── EFFICIENCY-findings-union-alpha.md # Benchmark findings & foundation recs
│       ├── REVIEW.md           # Architecture critique & gap analysis
│       └── REVIEW-union-alpha.md # Independent third-party review
├── Sources/
│   ├── UtterCore/              # Core modular business logic library
│   │   ├── Domain/             # SessionState state machine, DictationMode, TargetApplication
│   │   ├── Audio/              # 16 kHz mono Int16 capture & AudioLevelMeter
│   │   ├── Transcription/      # TranscriptionService, Mock, and FluidAudioProvider actor
│   │   ├── Refinement/         # OpenAI-compatible HTTP client & unslop prompt
│   │   ├── Insertion/          # KeySynthesizer, PasteboardManager, TargetValidator
│   │   ├── Storage/            # SafetyBuffer, StatsStore, VocabularyStore
│   │   ├── Hotkeys/            # ModifierKeyMonitor & event tap handlers
│   │   ├── UI/                 # IndicatorPanelController, PillViewModel, MenuBarManager
│   │   └── Coordinator/        # DictationCoordinator managing full session lifecycle
│   └── Utter/                  # Application executable entry point
│       └── main.swift          # NSApplicationDelegate setup and service binding
└── Tests/
    └── UtterTests/             # Unit test runner exercising core contracts
```

## Quick Start

### Prerequisites

- macOS 14.0 or later (Apple Silicon recommended)
- Swift 6.0+ toolchain (Xcode or Command Line Tools)

### Building and Testing

Build the application executable:
```bash
swift build --target Utter
```

Run the unit test suite:
```bash
swift run utter-test-runner
```

Run the application:
```bash
.build/debug/Utter
```

### Profiling Efficiency

Measure memory footprint and idle CPU:
```bash
./scripts/measure-efficiency.sh Utter
```
