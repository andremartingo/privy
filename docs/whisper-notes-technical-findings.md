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

## Publicly Inferred Architecture

This section describes the architecture that can be inferred from Whisper Notes' public website, App Store listing, FAQ, and privacy policy. It is not a reverse-engineered view of their private codebase. Exact implementation details, storage schema, model packaging, runtime libraries, and internal app modules are unknown.

### Core Local Transcription Flow

The public claims imply this flow:

```text
User records or imports media
    -> app stores source audio/video locally
    -> app selects a local speech model
    -> app prepares model/runtime on device
    -> app runs transcription locally
    -> app streams partial text to UI during processing
    -> app persists transcript locally
    -> user exports or shares manually
```

Important architectural constraints:

- Transcription is file/job based, not live transcription during recording.
- Partial text appears while the completed recording or imported file is being processed.
- The app must keep enough local state to restart or re-transcribe after iOS background interruption.
- Audio and transcript data stay in local app storage unless the user explicitly exports or shares.

### Capture Inputs

Whisper Notes appears to support multiple input surfaces:

- In-app voice recording.
- File import for audio files.
- File import or share handling for video files.
- Voice Memos share flow.
- WhatsApp/media share flow.
- iOS Lock Screen widget recording.
- iOS Control Center capture.
- iOS Action Button trigger.
- Siri/App Shortcuts trigger.
- Mac Fn-key dictation.
- Mac meeting recording for meeting apps.

For `privy`, these should be treated as different front doors into the same internal pipeline:

```text
Capture surface -> local media asset -> transcription job -> transcript record
```

Do not build separate transcription logic per surface.

### Model Runtime Layer

The public pages describe multiple model families: Whisper, Parakeet, Qwen3-ASR, and/or SenseVoice depending on page and platform. The exact implementation is not public, but the architecture implies a model registry with per-platform compatibility.

Likely responsibilities of this layer:

- Expose available models for the current device.
- Track model-specific language support.
- Select defaults by platform and language.
- Enforce minimum hardware requirements.
- Prepare/load model files.
- Run local inference.
- Emit text and timestamp segments.
- Report progress and failures.

For `privy`, model choice should be represented as app data, not hard-coded into views.

### Local Persistence Layer

Whisper Notes claims recordings and transcripts remain on-device and do not sync through their servers. That implies local persistence for:

- recordings
- imported media references or local copies
- transcript text
- timestamped transcript data
- language/model metadata
- exportable files or generated export content
- local AI outputs on Mac, such as titles, summaries, cleanup, and chat context

Unknowns:

- Whether recordings are stored in app container, shared app group, document storage, or a custom database.
- Whether transcripts are stored as files, SQLite/Core Data/SwiftData records, or another local database.
- Whether source media is copied or referenced in place after import.

### Export And Sharing Layer

Publicly stated export formats include TXT, SRT, and VTT. App Store copy also emphasizes subtitles and timestamped exports.

The architecture must therefore preserve enough timing data to generate subtitle files:

```text
Transcript segments -> format renderer -> local output file -> share sheet/save panel
```

For `privy`, export generation should be deterministic and testable. It should not depend on rendered SwiftUI text.

### Mac Fn-Key Dictation Flow

Whisper Notes' Mac product claims system-wide dictation by holding Fn in any app. That implies a distinct flow from memo transcription:

```text
Global hotkey down
    -> begin local recording
Global hotkey up
    -> stop recording
    -> local transcription
    -> optional cleanup
    -> insert text into currently focused app
```

Likely architecture requirements:

- global hotkey listener
- microphone permission
- Accessibility permission for text insertion
- active focused-app/text-field targeting
- background/menu-bar process behavior
- direct Mac distribution if App Store review blocks required permissions

For `privy`, this should be a separate feature module built on top of the same transcription client.

### Mac Meeting Recording Flow

The public FAQ claims meeting recording on Mac with auto-detection for Zoom, Teams, Google Meet, and similar platforms.

An inferred flow:

```text
Meeting app/browser detected
    -> user-consented recording starts
    -> microphone/system or meeting audio captured locally
    -> local recording saved
    -> transcription job runs locally
    -> transcript/summary stored locally
```

Unknowns:

- Whether system audio capture is implemented through ScreenCaptureKit, virtual audio routing, app-specific capture, or another mechanism.
- Whether meeting detection is process-based, window-title based, browser URL based, calendar based, or manual.
- Whether both local microphone and remote participant audio are captured.
- What permission prompts and legal consent flows are shown.

### iOS Extension And Shortcut Flow

The public pages mention Lock Screen widget, Control Center, Action Button, Siri, and Live Activities. A plausible architecture is:

```text
Widget/App Intent/Shortcut
    -> launch or wake app into recording mode
    -> store recording in app or app group container
    -> show Live Activity while recording
    -> return to app for transcription if needed
```

Important iOS limitation:

- Their FAQ says transcription stops when switching apps because iOS limits background GPU usage. This means the app likely performs heavy transcription only while foregrounded or after the user returns.

For `privy`, this implies a resumable job model and clear "tap to re-transcribe" behavior.

### Local AI Layer

Whisper Notes claims local AI features on Mac:

- cleanup
- titles
- summaries
- transcript chat

The likely flow:

```text
Completed transcript
    -> optional local cleanup model
    -> optional title/summary generation
    -> optional local retrieval/chat over transcript text
```

For `privy`, this is already partially covered by `FoundationModelsClient`, but the app should preserve original and cleaned transcripts separately.

### Network Boundary

The privacy policy and product pages imply a strict boundary:

```text
Default transcription path: no network
Default storage path: local only
Sharing/export path: user initiated
Analytics/tracking: none
Sync: none through Whisper Notes servers
```

For `privy`, equivalent claims require a release audit:

- inspect dependencies for network behavior
- remove analytics/tracking
- verify no crash logs include transcript/audio data
- test transcription while fully offline
- document exactly what leaves the device, if anything

### Unknown Internals

The following cannot be confirmed from public pages:

- Exact speech inference runtime.
- Exact model formats and quantization.
- Whether models are bundled or downloaded after install.
- Database/storage implementation.
- Segment schema.
- Audio preprocessing chain.
- Voice activity detection implementation.
- Silence skipping implementation.
- Punctuation and cleanup model implementation.
- Transcript chat retrieval method.
- Exact meeting recording capture API.
- Exact Mac hotkey and text insertion implementation.
- How they validate "zero network requests" in production.

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

## Public Model Findings

Whisper Notes appears to use a multi-model strategy rather than one speech model for every language and platform. The exact internal implementation is unknown, but the public model positioning is clear enough to guide `privy`'s architecture.

### Claimed Speech Models

| Model | Publicly claimed role | Platform notes | Language notes | Product implication |
| --- | --- | --- | --- | --- |
| Parakeet / Parakeet V3 | Fast default model, especially for English and European languages | Claimed as default on iPhone and Mac in the home FAQ | Public pages mention 25 European languages and low English WER | Use as the "fast/default" local model profile |
| Whisper Large V3 Turbo | Broad multilingual, high-accuracy general model | Claimed on Mac; App Store suggests Whisper is available on iOS too | 99 or 100+ languages depending on page | Use as the broad-language model profile |
| Qwen3-ASR | CJK-focused speech recognition | Mentioned on the Otter comparison page | Chinese, Japanese, Korean plus additional languages | Use as a possible CJK-optimized model profile |
| SenseVoice | CJK/Cantonese-focused speech recognition | Mentioned on the home FAQ for Mac | Chinese, Japanese, Korean, Cantonese | Another possible CJK-optimized profile; conflicts with Qwen3-ASR claim |
| Local LLM, described as Gemma 4 | Cleanup, title, summary, transcript questions | Claimed on Mac in the Otter comparison page | Not a speech model; used after transcription | Treat as a post-processing model, separate from ASR |

### Inferred Model Selection Logic

The public pages imply this selection strategy:

```text
If the user wants fastest/default transcription:
    use Parakeet / Parakeet V3

If the user needs broad multilingual support:
    use Whisper Large V3 Turbo or another Whisper model

If the user is transcribing Chinese, Japanese, Korean, or Cantonese:
    use CJK-specialized model such as Qwen3-ASR or SenseVoice

If transcription quality is poor:
    let the user switch models and manually select language
```

The app also appears to remember language preferences per model. That matters because model-specific language support differs; a single global language setting is not enough.

### Inferred Runtime Behavior

Public claims imply:

- Models run locally on the device.
- On iPhone, inference depends heavily on Neural Engine/GPU-class hardware.
- On Mac, the direct-download app targets Apple Silicon and recommends 8 GB+ RAM.
- Transcription runs after recording or import completes.
- Partial transcript text streams into the UI while the local model processes the completed audio file.
- iOS transcription can stop when the app backgrounds because iOS limits background GPU use.
- Large or higher-quality models may be unsuitable for older iPhones.

### Unknown Model Details

These details are not knowable from public pages:

- Whether models are Core ML, MLX, ONNX, GGML/GGUF, custom Metal, or another runtime format.
- Whether Whisper is implemented through `whisper.cpp`, WhisperKit, a custom runtime, or another engine.
- Whether models are bundled in the app, downloaded after install, or both.
- Exact model quantization.
- Exact memory requirements per model.
- Exact model file sizes.
- Exact fallback behavior when a model fails.
- Whether language detection is shared across engines or implemented per model.
- Whether punctuation and cleanup happen inside ASR decoding or as a separate post-processing step.

### Implication For Privy

`privy` should not hard-code a single transcription engine. We need a model registry and engine abstraction:

```swift
struct SpeechModel: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var engine: SpeechEngine
    var supportedLanguageCodes: [String]
    var defaultLanguageCode: String?
    var recommendedUse: ModelUseCase
    var minimumDeviceClass: DeviceClass
    var approximateDiskSize: Int64
    var supportsLanguageDetection: Bool
    var supportsStreamingOutput: Bool
    var supportsTimestamps: Bool
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

Recommended first implementation:

1. Ship one proven broad-language local model first.
2. Persist transcript segments and model metadata.
3. Add model switching only after the single-model pipeline is stable.
4. Add CJK-specific model support after import/export and job retry are reliable.

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
