import CasePaths
import Combine
import Dependencies
import FluidAudio
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class TranscriptStore: ObservableObject {
    @Published var state: State

    @Dependency(\.sampleAudioClient)
    private var sampleAudioClient
    @Dependency(\.foundationModelsClient)
    private var foundationModelsClient
    @Dependency(\.speechTranscriptionClient)
    private var speechTranscriptionClient
    @Dependency(\.exportClient)
    private var exportClient

    let memo: Binding<Memo>
    let speechTranscriber: SpokenWordTranscriber
    let diarizationManager: DiarizationManager

    private var recorder: Recorder?
    private var modelContext: ModelContext?
    private var progressTimer: Timer?
    private var playbackTimer: Timer?
    private var recordingTimer: Timer?
    private var recordingTask: Task<Void, Never>?
    private var settings: AppSettings?

    init(memo: Binding<Memo>, initialState: State = .init()) {
        @Dependency(\.speechTranscriptionClient)
        var speechTranscriptionClient

        self.memo = memo
        self.state = initialState

        let transcriber = speechTranscriptionClient.makeTranscriber(memo)
        self.speechTranscriber = transcriber
        self.diarizationManager = DiarizationManager(config: DiarizerConfig())

        self.state.showingEnhancedView = memo.summary.wrappedValue != nil

        transcriber.onTranscriptChanged = { [weak self] finalized, volatile in
            self?.state.finalizedTranscript = finalized
            self?.state.volatileTranscript = volatile
        }
    }

    func send(_ action: Action) async {
        CoreLogger.info(action.description)

        switch action {
        case let .onAppear(modelContext, settings):
            configure(modelContext: modelContext, settings: settings)
            await autoStartIfNeeded(settings: settings)

        case .onDisappear:
            cleanup()

        case .recordingButtonTapped:
            await toggleRecording()

        case .playButtonTapped:
            await togglePlayback()

        case .aiEnhanceButtonTapped:
            await generateAIEnhancements()

        case let .exportTapped(format):
            await export(format: format)

        case .exportDismissed:
            state.exportedURL = nil

        case .summaryToggleTapped:
            withAnimation(.smooth(duration: 0.3)) {
                state.showingEnhancedView.toggle()
                if state.showingEnhancedView {
                    state.showingSpeakerView = false
                }
            }

        case .speakerToggleTapped:
            withAnimation(.smooth(duration: 0.3)) {
                state.showingSpeakerView.toggle()
                if state.showingSpeakerView {
                    state.showingEnhancedView = false
                }
            }

        case .errorAlertDismissed:
            state.enhancementError = nil
            state.destination = nil
            state.exportError = nil
        }
    }

    private func configure(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
        self.settings = settings
        diarizationManager.config = settings.diarizationConfig()

        if recorder == nil {
            recorder = Recorder(
                transcriber: speechTranscriber,
                memo: memo,
                diarizationManager: diarizationManager,
                modelContext: modelContext
            )
        }

        connectDownloadProgress()
    }

    private func autoStartIfNeeded(settings: AppSettings) async {
        guard !memo.wrappedValue.isDone, memo.wrappedValue.text.characters.isEmpty else {
            syncPersistedTranscriptIfNeeded()
            return
        }

        speechTranscriber.reset()

        if settings.useSampleAudioForNewMemos {
            await transcribeSampleAudio()
        } else if let existingURL = memo.wrappedValue.recordingURL ?? memo.wrappedValue.url {
            await transcribeExistingAudio(from: existingURL)
        } else {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await startRecording()
        }
    }

    private func toggleRecording() async {
        if state.isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard !state.isProcessingSampleAudio else { return }

        state.isRecording = true
        startRecordingTimer()

        if memo.wrappedValue.isDone {
            memo.wrappedValue.isDone = false
            speechTranscriber.reset()
        }

        recordingTask = Task { @MainActor in
            do {
                try await recorder?.record()
                CoreLogger.info("recordingStarted")
            } catch let error as TranscriptionError {
                state.isRecording = false
                setError("Recording failed: \(error.descriptionString)")
            } catch {
                state.isRecording = false
                setError("Recording failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecording() async {
        stopRecordingTimer()
        state.isRecording = false

        do {
            try await recorder?.stopRecording()
            persistCurrentTranscriptSegment()
            await generateTitleIfNeeded()
            await generateAIEnhancements()
        } catch {
            memo.wrappedValue.transcriptionStatus = .failed
            memo.wrappedValue.errorMessage = error.localizedDescription
            setError("Error stopping recording: \(error.localizedDescription)")
        }
    }

    private func transcribeSampleAudio() async {
        guard !state.isProcessingSampleAudio else { return }
        guard let recorder else {
            setError("Sample transcription failed: recorder is not ready.")
            return
        }
        guard let sampleURL = sampleAudioClient.sampleURL() else {
            setError("Sample transcription failed: sample.mp3 was not found in the app bundle.")
            return
        }

        state.isProcessingSampleAudio = true

        do {
            try await recorder.transcribeSampleAudio(from: sampleURL)
            persistCurrentTranscriptSegment()
            await generateTitleIfNeeded()
            await generateAIEnhancements()
        } catch let error as TranscriptionError {
            memo.wrappedValue.transcriptionStatus = .failed
            memo.wrappedValue.errorMessage = error.descriptionString
            setError("Sample transcription failed: \(error.descriptionString)")
        } catch {
            memo.wrappedValue.transcriptionStatus = .failed
            memo.wrappedValue.errorMessage = error.localizedDescription
            setError("Sample transcription failed: \(error.localizedDescription)")
        }

        state.isProcessingSampleAudio = false
    }

    private func transcribeExistingAudio(from url: URL) async {
        guard !state.isProcessingSampleAudio else { return }
        guard let recorder else {
            setError("Transcription failed: recorder is not ready.")
            return
        }

        state.isProcessingSampleAudio = true

        do {
            try await recorder.transcribeAudioFile(from: url)
            persistCurrentTranscriptSegment()
            await generateTitleIfNeeded()
            await generateAIEnhancements()
        } catch let error as TranscriptionError {
            memo.wrappedValue.transcriptionStatus = .failed
            memo.wrappedValue.errorMessage = error.descriptionString
            setError("Transcription failed: \(error.descriptionString)")
        } catch {
            memo.wrappedValue.transcriptionStatus = .failed
            memo.wrappedValue.errorMessage = error.localizedDescription
            setError("Transcription failed: \(error.localizedDescription)")
        }

        state.isProcessingSampleAudio = false
    }

    private func togglePlayback() async {
        guard memo.wrappedValue.url != nil else { return }

        state.isPlaying.toggle()

        if state.isPlaying {
            await recorder?.playRecording()
            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.state.currentPlaybackTime = self?.recorder?.playerNode?.currentTime ?? 0.0
                }
            }
        } else {
            await recorder?.stopPlaying()
            state.currentPlaybackTime = 0
            playbackTimer?.invalidate()
            playbackTimer = nil
        }
    }

    private func generateAIEnhancements() async {
        let transcript = String(memo.wrappedValue.text.characters)

        state.isGenerating = true
        state.enhancementError = nil

        do {
            let enhancements = try await foundationModelsClient.generateEnhancements(transcript)
            memo.wrappedValue.summary = enhancements.summary
            memo.wrappedValue.title = enhancements.title

            withAnimation(.smooth(duration: 0.3)) {
                state.showingEnhancedView = true
            }
        } catch let error as FoundationModelsError {
            setError(error.localizedDescription)
        } catch {
            setError("Failed to generate AI enhancements: \(error.localizedDescription)")
        }

        state.isGenerating = false
    }

    private func export(format: ExportFormat) async {
        state.exportError = nil
        do {
            state.exportedURL = try await exportClient.export(memo.wrappedValue, format)
        } catch {
            state.exportError = error.localizedDescription
            state.destination = .errorAlert
        }
    }

    private func generateTitleIfNeeded() async {
        guard !memo.wrappedValue.text.characters.isEmpty,
            memo.wrappedValue.title == "New Memo" || memo.wrappedValue.title.isEmpty
        else {
            return
        }

        do {
            let suggestedTitle = try await foundationModelsClient.generateTitle(
                String(memo.wrappedValue.text.characters)
            )
            memo.wrappedValue.title = suggestedTitle
        } catch {
            CoreLogger.info("titleGenerationFailed: \(error.localizedDescription)")
        }
    }

    private func connectDownloadProgress() {
        guard progressTimer == nil, let progress = speechTranscriber.downloadProgress else { return }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                if progress.isFinished {
                    self.state.downloadProgress = 100
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                } else {
                    self.state.downloadProgress = progress.fractionCompleted * 100
                }
            }
        }
    }

    private func startRecordingTimer() {
        state.recordingStartTime = Date()
        state.recordingDuration = 0
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startTime = self.state.recordingStartTime else { return }
                self.state.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        state.recordingStartTime = nil
        state.recordingDuration = 0
    }

    private func setError(_ message: String) {
        state.enhancementError = message
        state.destination = .errorAlert
    }

    private func syncPersistedTranscriptIfNeeded() {
        guard memo.wrappedValue.transcriptText.isEmpty,
            !memo.wrappedValue.text.characters.isEmpty
        else {
            return
        }

        memo.wrappedValue.transcriptText = String(memo.wrappedValue.text.characters)
    }

    private func persistCurrentTranscriptSegment() {
        guard let modelContext else { return }

        let transcript = String(memo.wrappedValue.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        memo.wrappedValue.updateTranscript(
            transcript,
            modelId: settings?.modelId ?? TranscriptionOptions.default.modelId,
            languageCode: settings?.languageCode ?? TranscriptionOptions.default.languageCode
        )

        if let settings {
            let cleanedTranscript = TranscriptPostProcessor.process(transcript, settings: settings)
            memo.wrappedValue.cleanedTranscriptText = cleanedTranscript == transcript
                ? nil
                : cleanedTranscript
        }

        if memo.wrappedValue.transcriptSegments.isEmpty {
            let segment = TranscriptSegment(
                startTime: 0,
                endTime: max(memo.wrappedValue.duration ?? 5, 5),
                text: transcript,
                modelId: settings?.modelId ?? TranscriptionOptions.default.modelId,
                languageCode: settings?.languageCode ?? TranscriptionOptions.default.languageCode
            )
            memo.wrappedValue.replaceTranscriptSegments([segment], in: modelContext)
        }

        alignSpeakersToTranscriptSegments()
    }

    private func alignSpeakersToTranscriptSegments() {
        let transcriptSegments = memo.wrappedValue.transcriptSegments
        guard !transcriptSegments.isEmpty, !memo.wrappedValue.speakerSegments.isEmpty else {
            return
        }

        for speakerSegment in memo.wrappedValue.speakerSegments {
            let overlappingText = transcriptSegments
                .filter { transcriptSegment in
                    transcriptSegment.startTime < speakerSegment.endTime
                        && speakerSegment.startTime < transcriptSegment.endTime
                }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !overlappingText.isEmpty {
                speakerSegment.text = overlappingText
            }
        }
    }

    private func cleanup() {
        progressTimer?.invalidate()
        progressTimer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTask?.cancel()
        recordingTask = nil
    }
}

extension TranscriptStore {
    struct State: Equatable {
        var isRecording = false
        var isPlaying = false
        var isGenerating = false
        var isProcessingSampleAudio = false
        var downloadProgress = 0.0
        var currentPlaybackTime = 0.0
        var recordingStartTime: Date?
        var recordingDuration: TimeInterval = 0
        var showingEnhancedView = false
        var showingSpeakerView = false
        var isEditingSummary = false
        var enhancementError: String?
        var exportError: String?
        var exportedURL: URL?
        var finalizedTranscript = AttributedString("")
        var volatileTranscript = AttributedString("")
        var destination: Destination?

        @CasePathable
        enum Destination: Equatable {
            case errorAlert
        }
    }

    enum Action {
        case onAppear(ModelContext, AppSettings)
        case onDisappear
        case recordingButtonTapped
        case playButtonTapped
        case aiEnhanceButtonTapped
        case exportTapped(ExportFormat)
        case exportDismissed
        case summaryToggleTapped
        case speakerToggleTapped
        case errorAlertDismissed

        var description: String {
            switch self {
            case .onAppear:
                return "onAppear"
            case .onDisappear:
                return "onDisappear"
            case .recordingButtonTapped:
                return "recordingButtonTapped"
            case .playButtonTapped:
                return "playButtonTapped"
            case .aiEnhanceButtonTapped:
                return "aiEnhanceButtonTapped"
            case .exportTapped:
                return "exportTapped"
            case .exportDismissed:
                return "exportDismissed"
            case .summaryToggleTapped:
                return "summaryToggleTapped"
            case .speakerToggleTapped:
                return "speakerToggleTapped"
            case .errorAlertDismissed:
                return "errorAlertDismissed"
            }
        }
    }
}
