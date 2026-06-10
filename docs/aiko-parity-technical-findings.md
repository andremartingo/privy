# Aiko Parity Technical Findings

Date: 2026-06-10

## Objective

This document summarizes the technical findings from investigating Aiko and comparing it with the current `privy` codebase. The goal is not to copy Aiko's brand, assets, UI text, screenshots, icon, or protected expression. The goal is to understand the product and engineering capabilities required to build a similar privacy-first, on-device transcription app.

Primary references:

- Aiko product page: https://sindresorhus.com/aiko
- Aiko App Store listing: https://apps.apple.com/app/id1672085276
- Aiko privacy policy: https://github.com/sindresorhus/privacy-policy/blob/main/aiko.md

## Aiko Product Findings

Aiko is a native Apple-platform transcription app focused on high-quality local transcription. The product positioning is clear: audio stays on-device, transcription quality is prioritized over speed, and the app supports many languages and export workflows.

Key product capabilities:

- On-device transcription using OpenAI Whisper.
- macOS, iOS, iPadOS, and visionOS support.
- Universal Purchase.
- 14-day TestFlight trial.
- Audio and video file transcription.
- Recording transcription.
- Support for 100 languages.
- Local privacy model with no data collection.
- Export to multiple formats, including subtitle formats.
- Shortcuts integration for batch-like and automation workflows.
- Finder Quick Actions on macOS through Shortcuts.

Important stated limitations:

- No live transcription.
- iOS app must remain open while transcribing.
- No in-app transcript editing.
- No speaker diarization yet.
- No built-in batch transcription, though Shortcuts can approximate it.
- No `.ogg` support because Apple platform media APIs do not support it.
- Translation is limited to English because that is what Whisper's translation mode supports.
- Repetitions, missing punctuation, hallucinated ending phrases, and Traditional/Simplified Chinese inconsistency are treated as Whisper model limitations.

## Current Privy Architecture

The current app already follows the project's View -> Store pattern:

- `privy/Views/ContentView.swift`
- `privy/Content/ContentStore.swift`
- `privy/Transcript/TranscriptView.swift`
- `privy/Transcript/TranscriptStore.swift`
- `privy/Clients/SpeechTranscriptionClient.swift`
- `privy/Audio/Recorder.swift`
- `privy/Models/MemoModel.swift`
- `privy/Models/AppSettings.swift`

Current capabilities:

- SwiftUI app with iOS and macOS support.
- SwiftData persistence for memos and speakers.
- Recording from the microphone.
- Live transcription using Apple's `SpeechTranscriber`.
- Playback of recorded audio.
- AI title and summary generation through `FoundationModels`.
- Speaker diarization using FluidAudio.
- Basic settings for appearance, sample audio, and diarization.

Current architectural strengths:

- Existing store pattern maps well to a transcription job workflow.
- Dependency clients are already used, so replacing the transcription engine can be done behind a client boundary.
- SwiftData is already available for durable transcript, recording, segment, and export metadata.
- The app already separates content navigation from transcript detail behavior.
- Diarization is already explored, even though alignment currently needs stronger modeling.

Current architectural risks:

- Transcription is currently stream-oriented and tied to Apple's `SpeechTranscriber`.
- The app is effectively English-first because `SpokenWordTranscriber.locale` is fixed to English with fallback English locales.
- Transcription state is not modeled as a durable job with progress, cancellation, failure, and retry.
- Transcript segments with timestamps are not stored as first-class data.
- Export workflows are not implemented.
- File import is not implemented as a first-class path.
- The current diarization text alignment is proportional by character count, which is too approximate for production.
- Debug `print` calls are widespread in transcription and recording paths.

## Major Parity Gap

The largest gap is the transcription engine.

Aiko's core value comes from local Whisper transcription. `privy` currently uses Apple's `SpeechTranscriber`, which has different tradeoffs:

- Fewer languages than Whisper.
- Different accuracy profile.
- Strong OS-version dependency.
- Current implementation is live stream based.
- Current implementation does not provide the same file-based segment/export workflow expected from an Aiko-like app.

To become Aiko-like, `privy` should move from:

```text
Microphone buffer -> Apple SpeechTranscriber -> live memo text
```

to:

```text
Record/import media file -> local Whisper job -> timestamped segments -> persisted transcript -> export/share
```

## Recommended Core Model

Introduce first-class transcription concepts instead of treating transcript text as the only durable output.

Suggested model additions:

```swift
enum TranscriptionStatus: String, Codable {
    case pending
    case preparing
    case transcribing
    case completed
    case failed
    case cancelled
}

@Model
final class TranscriptSegment {
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var speakerId: String?
    var confidence: Double?
}
```

Suggested `Memo` additions:

- `sourceURL: URL?`
- `recordingURL: URL?`
- `transcriptText: String`
- `languageCode: String?`
- `detectedLanguageCode: String?`
- `duration: TimeInterval?`
- `status: TranscriptionStatus`
- `progress: Double`
- `errorMessage: String?`
- `segments: [TranscriptSegment]`

The current `AttributedString` text can remain for display, but the source of truth should become structured plain text plus segments.

## Recommended Client Boundaries

The current dependency-client style should be preserved.

Recommended clients:

```swift
struct TranscriptionClient {
    var prepare: @Sendable () async throws -> Void
    var transcribe: @Sendable (URL, TranscriptionOptions) async throws -> AsyncThrowingStream<TranscriptionEvent, Error>
}

struct AudioImportClient {
    var importMedia: @Sendable (URL) async throws -> ImportedAudio
    var extractAudio: @Sendable (URL) async throws -> URL
}

struct ExportClient {
    var export: @Sendable (Memo, ExportFormat) async throws -> URL
}

struct ModelManagementClient {
    var availableModels: @Sendable () async -> [SpeechModel]
    var ensureModel: @Sendable (SpeechModel) async throws -> Progress
    var deleteModel: @Sendable (SpeechModel) async throws -> Void
}
```

Suggested transcription events:

```swift
enum TranscriptionEvent: Sendable {
    case progress(Double)
    case partialText(String)
    case segment(TranscriptSegmentPayload)
    case completed(TranscriptionResult)
}
```

## Whisper Engine Options

The app needs a local Whisper-compatible runtime. Practical options:

1. `whisper.cpp`
   - Strong fit for local, offline transcription.
   - Proven and widely used.
   - Requires native integration, model packaging/downloading, and platform tuning.

2. WhisperKit
   - Apple-platform focused.
   - Potentially smoother Swift integration.
   - Evaluate model support, performance, binary size, and license constraints.

3. Existing FluidAudio ecosystem
   - Already in the app for diarization.
   - Worth evaluating only if it provides production-grade ASR/transcription that meets the same quality/language expectations.

Recommendation: prototype `whisper.cpp` or WhisperKit behind `TranscriptionClient` before making any UI changes. The engine decision will determine model format, download strategy, performance, memory behavior, and deployment targets.

## Recording Flow Changes

Current flow:

```text
Start recording -> stream buffers to Apple SpeechTranscriber -> append live text -> stop -> finalize
```

Recommended flow:

```text
Start recording -> write audio file -> stop recording -> create transcription job -> run Whisper -> persist result
```

Required changes:

- Refactor `Recorder` to focus on capture and playback only.
- Move transcription out of `Recorder`.
- Save recordings into an app-managed recordings directory instead of temporary URLs.
- Add automatic cleanup based on user settings.
- Keep the screen awake during long transcription where platform APIs allow.
- Show progress and cancellation while transcription is running.

## Import Flow Changes

Aiko supports transcription from audio and video files that Apple platforms can read. `privy` should add:

- `fileImporter` on iOS/macOS.
- Share handling for external files.
- UTType declarations for audio and video.
- Audio extraction from video through `AVAsset`.
- Unsupported-format errors for formats such as `.ogg`.
- Optional conversion guidance instead of silent failure.

The import path should create a memo first, attach the source file, then enqueue transcription.

## Export Requirements

Export should be based on structured transcript segments.

Recommended formats:

- Plain text.
- Timestamped text.
- SRT.
- WebVTT.
- JSON.
- CSV.

Recommended implementation:

- Add `ExportFormat`.
- Add `ExportClient`.
- Use one formatter per output format.
- Make export available from the transcript toolbar and share sheet.
- Keep file generation deterministic and testable.

## Settings Requirements

Current settings are not enough for an Aiko-like app.

Recommended settings:

- Transcription model selection.
- Automatic language detection.
- Forced source language.
- Translate to English.
- Initial prompt.
- Produce timestamps.
- Skip silent parts.
- Reduce repetitions.
- Stronger repetition reduction.
- Auto-delete recordings older than 7 days.
- Word replacements.
- Diarization enabled.
- Maximum speaker count.
- Appearance.

Settings should live in `AppSettings`, but model selection and downloaded-model state should likely be persisted separately because it affects storage and runtime behavior.

## Diarization Findings

`privy` already has diarization through FluidAudio, which is beyond Aiko's currently stated feature set. This can be a differentiator, but the implementation needs improvement before it can be marketed as reliable speaker labeling.

Current issue:

- `Recorder.alignTranscriptionWithSpeakers(_:)` distributes transcript text proportionally across speaker segments.

Recommended approach:

- Store Whisper timestamp segments.
- Store diarization speaker segments.
- Align by overlapping time ranges.
- Merge adjacent segments from the same speaker.
- Allow manual speaker renaming.

## UI Implications

Most Aiko-like behavior is backend and workflow work, not just UI work.

Recommended UI states:

- Empty library.
- Imported/recorded but not transcribed.
- Preparing model.
- Downloading model.
- Transcribing with progress.
- Completed transcript.
- Failed transcription with retry.
- Export/share sheet.
- Recording cleanup settings.

The current `TranscriptView` can be adapted, but it should stop assuming that transcription is live while recording.

## Privacy Requirements

To match Aiko's privacy positioning:

- Transcription must run locally.
- No transcript or audio should leave the device by default.
- If optional AI summaries use Foundation Models, make clear that they are local when available.
- Avoid analytics unless explicitly documented and opt-in.
- Add a privacy policy matching actual behavior.
- Ensure exported files are user-initiated.

## Legal And Product Boundaries

Do not copy:

- Aiko name.
- Aiko icon.
- Aiko screenshots.
- Aiko exact marketing copy.
- Aiko FAQ text.
- Aiko UI arrangement if it is being replicated as trade dress.

Safe direction:

- Build an original local transcription app.
- Use local Whisper or equivalent models.
- Offer similar standard features: import, record, transcribe, export, privacy, shortcuts, settings.
- Brand, visual design, and copy should be original.

## Implementation Roadmap

### Phase 1: Engine Prototype

- Add `TranscriptionClient`.
- Prototype local Whisper on one known audio file.
- Return plain text plus timestamped segments.
- Measure speed, memory, and model size on target devices.
- Decide between `whisper.cpp`, WhisperKit, or another local runtime.

### Phase 2: Job-Based Transcription

- Add transcription status/progress to `Memo`.
- Refactor `Recorder` to record first and transcribe after stop.
- Add cancellation and retry.
- Persist segments.
- Keep summary generation optional and post-transcription.

### Phase 3: Import And Export

- Add file import.
- Add video audio extraction.
- Add export client.
- Implement TXT, timestamped TXT, SRT, VTT, JSON, and CSV.
- Add share sheet and macOS save panel integration.

### Phase 4: Model And Settings

- Add model selection.
- Add model download/availability state.
- Add language settings.
- Add prompt, translation, timestamps, silence skipping, and repetition reduction settings.
- Add recording auto-delete.

### Phase 5: Diarization Quality

- Align speakers by timestamp overlap.
- Persist speaker labels cleanly.
- Add speaker rename UI.
- Add diarized export variants.

### Phase 6: Automation And Platform Polish

- Add App Shortcuts.
- Add Finder Quick Action guidance or shortcuts.
- Add share extension if needed.
- Add trial/purchase infrastructure if this becomes a paid app.
- Add accessibility verification.

## Testing Strategy

Unit tests:

- Export format generation.
- Timestamp formatting.
- Segment merging.
- Speaker alignment.
- Word replacement.
- Settings persistence.

Integration tests:

- Import audio file and transcribe.
- Import video file and extract audio.
- Cancel transcription.
- Retry failed transcription.
- Delete old recordings.

Manual QA:

- Long audio file.
- Noisy audio.
- Silent audio.
- Multiple languages.
- Large model on macOS.
- Smaller model on iPhone.
- Low-storage device behavior.
- Backgrounding during transcription on iOS.

## Recommended Next Step

Start with a narrow engine spike. Implement `TranscriptionClient` behind the existing dependency pattern and transcribe `privy/sample.mp3` from a local Whisper model. Do not redesign the UI until the engine, model size, progress reporting, and memory behavior are proven.

