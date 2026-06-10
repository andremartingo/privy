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

    let memo: Binding<Memo>
    let speechTranscriber: SpokenWordTranscriber
    let diarizationManager: DiarizationManager

    private var recorder: Recorder?
    private var modelContext: ModelContext?
    private var progressTimer: Timer?
    private var playbackTimer: Timer?
    private var recordingTimer: Timer?
    private var recordingTask: Task<Void, Never>?

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
        }
    }

    private func configure(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
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
            return
        }

        speechTranscriber.reset()

        if settings.useSampleAudioForNewMemos {
            await transcribeSampleAudio()
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
            await generateTitleIfNeeded()
            await generateAIEnhancements()
        } catch {
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
            await generateTitleIfNeeded()
            await generateAIEnhancements()
        } catch let error as TranscriptionError {
            setError("Sample transcription failed: \(error.descriptionString)")
        } catch {
            setError("Sample transcription failed: \(error.localizedDescription)")
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
