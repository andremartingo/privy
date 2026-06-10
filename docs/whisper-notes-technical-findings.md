# Whisper Notes Technical Findings

Date: 2026-06-10

## Objective

This document summarizes findings from investigating Whisper Notes, especially its comparison page against Otter.ai, and maps the implications for `privy`. The goal is not to copy Whisper Notes' brand, copy, assets, screenshots, or protected expression. The goal is to identify the product and technical capabilities needed for a privacy-first, local transcription app that can compete in the same category.

Primary references:

- Whisper Notes vs Otter.ai: https://whispernotes.app/whisper-notes-vs-otter-ai
- Whisper Notes home/FAQ: https://whispernotes.app/
- Whisper Notes App Store listing: https://apps.apple.com/app/id6447090616
- Whisper Notes privacy policy: https://whispernotes.app/privacy
- Otter.ai pricing page: https://otter.ai/pricing

## High-Level Product Findings

Whisper Notes positions itself as a low-cost, offline alternative to cloud transcription products such as Otter.ai. Its primary differentiation is architectural: audio stays on the user's device, transcription runs locally, and there is no recurring subscription.

Core product claims:

- 100% offline transcription on iPhone and Mac.
- No cloud uploads.
- No analytics or tracking.
- One-time purchase pricing.
- Import audio and video files.
- Record voice memos.
- Export TXT, SRT, and VTT.
- Multiple speech models.
- 100+ language support.
- Mac Fn-key dictation into any app.
- Mac meeting recording for Zoom, Teams, Google Meet, and similar apps.
- iOS Lock Screen widget, Control Center, Action Button, and Siri capture flows.
- Live Activity and Dynamic Island recording status on iOS.
- Streaming transcription output after recording or file import.
- Local AI cleanup, titles, summaries, and transcript chat on Mac.

The app deliberately gives up some cloud-first product capabilities:

- No automatic sync through Whisper Notes servers.
- No collaborative transcript workspace.
- No browser-based transcript access.
- No meeting bot that joins calls remotely.
- No live transcription during recording, though processed text streams during transcription.
- Speaker identification is not currently positioned as a strength.

## Pricing And Market Positioning

Whisper Notes' positioning is aggressively price-led:

- iOS/iPadOS: $6.99 one-time purchase.
- Mac: free trial with 10,000 words, then $6.99 one-time unlock.
- iOS and Mac are separate purchases, not a Universal Purchase.
- No subscriptions, no ads, no in-app purchase upsells stated on the App Store listing.

The comparison page frames Otter.ai as a subscription cloud product. Otter's official pricing page currently lists:

- Basic: free, 300 monthly transcription minutes, 3 lifetime file imports.
- Pro annual: $8.33/user/month, 1,200 in-app recording minutes, 10 monthly audio/video file imports, up to 90 minutes per meeting.
- Pro monthly: $16.99/user/month.
- Business annual: $19.99/user/month, unlimited meetings and in-app recordings, 6,000 imported-file minutes, up to 4 hours per meeting.
- Business monthly: $30/user/month.
- Enterprise: custom pricing.

Whisper Notes' comparison page says Otter Pro is $99.99/year and Otter Business is $240/year. Otter's official page now exposes slightly different annual effective prices in places, so any user-facing comparison should be verified at launch time and should avoid hard-coded competitor pricing unless we plan to maintain it.

## Architecture Positioning

Whisper Notes frames the core architecture this way:

```text
Audio stays on device -> local model runs on Neural Engine/GPU -> transcripts stay on device
```

This is contrasted against Otter's cloud architecture:

```text
Audio uploaded -> cloud GPUs process it -> transcripts stored in cloud -> user accesses via web/app
```

For `privy`, the product implication is clear: the technical architecture itself is the marketing claim. We cannot credibly claim Whisper Notes-style privacy if any default transcription, summary, analytics, crash logging, or sync path uploads user audio or transcript text.

## Current Privy Comparison

Current `privy` already has several pieces that map to this category:

- SwiftUI iOS/macOS app.
- SwiftData memo persistence.
- View -> Store pattern.
- Recording.
- Playback.
- Transcript display.
- Local Foundation Models title/summary generation.
- FluidAudio diarization exploration.
- Settings infrastructure.

Current gaps against Whisper Notes:

- `privy` uses Apple's `SpeechTranscriber`, not Whisper, Parakeet, or another bundled local ASR model.
- Current transcription is live-stream oriented instead of record/import -> transcribe job oriented.
- No model switching.
- No audio/video import workflow.
- No export workflow for SRT, VTT, or TXT.
- No iOS Lock Screen widget.
- No Live Activity / Dynamic Island recording status.
- No Control Center or Action Button flow.
- No Siri/App Shortcuts flow.
- No Mac Fn-key global dictation.
- No Mac meeting recording workflow.
- No local transcript chat UI.
- No privacy policy or product-surface privacy guarantees.
- No durable transcription job model with progress, cancellation, retry, and failure state.

## Source Inconsistencies To Verify

Whisper Notes' own pages contain some model naming differences:

- The comparison page says Whisper Notes supports Whisper Large V3 Turbo, Parakeet V3, and Qwen3-ASR.
- The home FAQ says iPhone uses Parakeet and Whisper, while Mac offers Parakeet V3, Whisper Large V3 Turbo, and SenseVoice for Chinese, Japanese, Korean, and Cantonese.
- The App Store text says multiple models such as Parakeet and Whisper, without fully matching every website claim.

For our implementation, the lesson is not to copy their model matrix. The right path is to design a model abstraction that can support multiple engines and expose only the models we actually ship and test.

## Feature Implications For Privy

### 1. Multi-Model Transcription

Whisper Notes' strongest technical signal is model choice. A comparable product should support more than one model profile:

- Fast English/default model.
- Broad multilingual model.
- CJK-optimized model.
- Optional larger model for newer devices.

Recommended abstraction:

```swift
struct SpeechModel: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var engine: SpeechEngine
    var supportedLanguageCodes: [String]
    var recommendedUse: ModelUseCase
    var minimumDeviceClass: DeviceClass
    var approximateDiskSize: Int64
    var supportsStreamingOutput: Bool
    var supportsTranslation: Bool
}

enum SpeechEngine: String, Codable, Sendable {
    case whisper
    case parakeet
    case senseVoice
    case qwenASR
    case appleSpeech
}
```

The current `SpeechTranscriptionClient` should become an engine-agnostic `TranscriptionClient`.

### 2. Job-Based Transcription

Whisper Notes transcribes after recording or import. Text appears gradually during processing, but the source is a finished file, not live microphone streaming.

Recommended flow:

```text
Record or import media -> create memo -> create transcription job -> process file -> stream partial results -> persist segments -> export/share
```

This requires durable state:

```swift
enum TranscriptionStatus: String, Codable {
    case idle
    case recording
    case queued
    case preparingModel
    case transcribing
    case completed
    case failed
    case cancelled
}
```

### 3. Structured Transcript Segments

Export, playback sync, timestamped review, speaker alignment, and transcript chat all need structured transcript segments.

Suggested model:

```swift
@Model
final class TranscriptSegment {
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var modelId: String
    var languageCode: String?
    var confidence: Double?
    var speakerId: String?
}
```

The current `Memo.text: AttributedString` can remain a display artifact, but the source of truth should be plain text plus timestamped segments.

### 4. Audio And Video Import

Whisper Notes emphasizes importing audio/video from other apps, Voice Memos, WhatsApp, and Photos.

Recommended components:

- `AudioImportClient`
- `MediaExtractionClient`
- `UTType` support for audio/video
- `fileImporter`
- share extension or document type handling
- Voice Memos share handling
- Photos video import
- unsupported-format errors

The initial implementation should handle:

- `.mp3`
- `.m4a`
- `.wav`
- `.mp4`
- `.mov`

### 5. Export Formats

Whisper Notes' App Store listing specifically mentions SRT, VTT, and TXT. Otter's official page lists exports such as MP3, TXT, PDF, DOCX, and SRT depending on plan.

Recommended `privy` export targets:

- TXT
- TXT with timestamps
- SRT
- VTT
- JSON
- CSV
- Optional DOCX/PDF later

Export should be generated from `TranscriptSegment`, not from rendered UI text.

### 6. Mac Fn-Key Dictation

This is one of Whisper Notes' major differentiators on Mac. It is also one of the more complex features.

Technical implications:

- Global hotkey registration.
- Accessibility permission.
- Text insertion into the focused app.
- Recording lifecycle independent of the main window.
- Menu bar or background helper behavior.
- Clear onboarding for permissions.

This likely requires a direct-distribution Mac build. Whisper Notes says its Mac App Store version is no longer maintained because Apple required removal of Accessibility permissions that broke Fn-key voice typing. If we want this feature, distribution strategy matters.

### 7. Meeting Recording On Mac

Whisper Notes claims Mac meeting recording for Teams, Google Meet, Zoom, and most other platforms, with local transcription.

Technical implications:

- System audio capture or meeting-app audio capture.
- Microphone capture.
- Permission onboarding.
- Meeting-app detection.
- Potential ScreenCaptureKit usage.
- User consent and legal disclosure UX.
- Direct-download build may be required depending on entitlement and review constraints.

This should be treated as a later phase, not part of the first transcription engine spike.

### 8. iOS Capture Surfaces

Whisper Notes highlights capture from:

- Lock Screen widget.
- Control Center.
- Action Button.
- Siri.
- Voice Memos share sheet.
- Live Activity / Dynamic Island during recording.

Technical implications:

- Widget extension.
- App Intents.
- App Shortcuts.
- Control Widget if targeting newer iOS versions.
- Live Activities.
- Shared app group storage if extensions create recordings or enqueue jobs.
- Clear behavior when app is launched from a widget or shortcut.

`privy` already targets very new OS versions, so these APIs are feasible, but they should be built after the core record/import/transcribe workflow is stable.

### 9. Local AI Cleanup And Chat

Whisper Notes' website claims Mac-only local AI features:

- punctuation and grammar cleanup
- filler word removal
- generated titles
- summaries
- transcript Q&A/chat

`privy` already has local Foundation Models title and summary generation, which is a meaningful advantage. The missing pieces are:

- explicit post-transcription cleanup
- filler-word removal
- transcript question answering
- long-transcript chunking with citations or segment references
- feature gating by platform/model availability

Recommended approach:

- Keep transcription independent of local LLM features.
- Run cleanup as an optional post-processing step.
- Preserve original transcript and store cleaned transcript separately.
- For transcript chat, answer from transcript segments and include timestamp references.

### 10. Privacy Claims

Whisper Notes makes very strong privacy claims:

- no analytics
- no tracking
- no transcription servers
- audio and transcripts stay on device
- data leaves only if the user shares it

To make equivalent claims, `privy` needs:

- No network calls in default transcription or summarization paths.
- No analytics SDK.
- No remote crash reporting that includes transcript/audio metadata.
- A clear privacy policy.
- App Store privacy nutrition label set to no data collection if true.
- A network audit before release.

## Hardware And OS Requirements

Whisper Notes' website recommends:

- iPhone 12 and later.
- M-series Macs.
- 8 GB+ RAM on Mac.
- No Intel Mac support for the direct Mac product.

The App Store listing says:

- iOS 18.0 or later and A12 Bionic or later.
- macOS 14.0 or later.
- visionOS 2.0 or later.

The App Store reviews include a hardware-related complaint from an iPhone SE 2nd generation user, with a developer response saying the issue is RAM and that iPhone 12 or newer is generally required.

Implication for `privy`:

- Do not rely only on Apple's App Store compatibility list.
- Add runtime checks for device class, RAM, Neural Engine/GPU capability, and model size.
- Disable or hide large models on unsupported devices.
- Provide preflight warnings before purchase or before model download where possible.

## Competitive Positioning Lessons

Whisper Notes is not just selling transcription. It is selling a bundle of constraints:

- local-first
- simple
- cheap
- offline
- private
- fast enough
- model choice
- capture anywhere

For `privy`, matching every feature is less important than choosing a coherent wedge. The clearest wedge based on current code is:

```text
Private local transcription + structured notes + summaries + optional speaker view
```

This differs from Whisper Notes if we keep and improve diarization and summaries while staying offline.

## Recommended Architecture Changes

### Replace `SpeechTranscriptionClient`

Current file:

- `privy/Clients/SpeechTranscriptionClient.swift`

Recommended direction:

- Rename or replace with `TranscriptionClient`.
- Keep `SpeechTranscriptionClient` only as a fallback or debug implementation.
- Add model selection to the transcription options.
- Return events instead of directly mutating memo text.

Suggested shape:

```swift
struct TranscriptionClient: Sendable {
    var transcribe: @Sendable (URL, TranscriptionOptions) async throws -> AsyncThrowingStream<TranscriptionEvent, Error>
}

struct TranscriptionOptions: Codable, Equatable, Sendable {
    var modelId: String
    var languageCode: String?
    var detectLanguage: Bool
    var translateToEnglish: Bool
    var prompt: String?
    var timestampsEnabled: Bool
    var cleanupEnabled: Bool
}
```

### Refactor `Recorder`

Current file:

- `privy/Audio/Recorder.swift`

Recommended direction:

- Make `Recorder` responsible for audio capture and playback only.
- Remove direct transcription streaming from `Recorder`.
- Remove diarization from the recording loop.
- Save recordings to a durable app recordings directory.
- Emit recording lifecycle events to `TranscriptStore`.

### Expand `Memo`

Current file:

- `privy/Models/MemoModel.swift`

Recommended additions:

- source media URL
- recording URL
- transcription status
- model ID
- language metadata
- plain transcript text
- cleaned transcript text
- timestamp segments
- export metadata
- error state

### Keep `FoundationModelsClient`, But Decouple It

Current file:

- `privy/Clients/FoundationModelsClient.swift`

Keep this as an optional local post-processing client. It should not run automatically if transcription fails, and it should not block completion of the raw transcript.

Recommended additions:

- cleanup transcript
- remove filler words
- generate title
- summarize with chunking
- answer question from transcript with timestamp citations

## Roadmap Impact

### Phase 1: Local Engine Spike

- Build `TranscriptionClient`.
- Test one local model against `privy/sample.mp3`.
- Emit text segments with timestamps.
- Measure speed and memory on Mac.
- Decide initial iOS model constraints.

### Phase 2: Record-Then-Transcribe

- Refactor `Recorder`.
- Add durable recording URLs.
- Add transcription job status to `Memo`.
- Show progress and streaming text after recording.
- Add retry after iOS background interruption.

### Phase 3: Import And Export

- Add file import.
- Add share handling.
- Add Voice Memos import path.
- Add TXT, timestamped TXT, SRT, VTT, JSON, and CSV export.

### Phase 4: Model Selection

- Add model picker.
- Add language picker.
- Add per-model language preference.
- Add device/model compatibility checks.
- Add model download or bundled model strategy.

### Phase 5: iOS Capture Surfaces

- Add App Intents.
- Add App Shortcuts.
- Add Action Button-compatible recording shortcut.
- Add Lock Screen widget.
- Add Live Activity / Dynamic Island recording status.

### Phase 6: Mac Capture Surfaces

- Add menu bar mode.
- Add global hotkey recording.
- Add Accessibility permission onboarding.
- Add text insertion into focused app.
- Evaluate meeting recording feasibility.

### Phase 7: Local AI Notes

- Add cleaned transcript.
- Preserve original transcript.
- Add local summary/title generation.
- Add transcript chat with timestamp references.
- Add optional action item extraction.

## Testing Strategy

Unit tests:

- Transcription event reduction into memo state.
- Timestamp formatting.
- SRT and VTT generation.
- TXT export.
- Model compatibility rules.
- Settings persistence.
- Filler-word cleanup preserving original transcript.

Integration tests:

- Record audio -> transcribe -> persist.
- Import `.m4a` -> transcribe -> export SRT.
- Import video -> extract audio -> transcribe.
- Cancel transcription.
- Background iOS app during transcription -> return -> retry.
- Switch models and language preferences.

Manual QA:

- iPhone 12 baseline.
- Newer iPhone Pro.
- M1 Mac with 8 GB RAM.
- Long recording over 90 minutes.
- Multi-hour import.
- Poor network/offline mode.
- Noisy audio.
- Multi-language audio.
- CJK audio.
- Low storage.
- First run without model installed.

## Product Risks

- Local model performance can make or break the product.
- Older iPhones may technically install but deliver unacceptable behavior.
- Direct Mac distribution may be necessary for Fn-key dictation and meeting recording.
- Strong privacy claims require strict network discipline.
- Multiple models increase support complexity.
- Model names and benchmarks change quickly; marketing copy must be easy to update.
- App Store review may constrain background recording, Accessibility usage, and meeting capture behavior.

## Recommended Next Step

The next engineering step is the same as the Aiko investigation but with a stronger model-management requirement: implement a narrow `TranscriptionClient` spike that transcribes `privy/sample.mp3` from a local model and returns timestamped segments. Once that works, design model selection and job state around the actual runtime constraints instead of starting with UI.

