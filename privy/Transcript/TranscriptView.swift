import CoreMedia
import Foundation
import SwiftData
import SwiftUI

struct TranscriptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @StateObject private var store: TranscriptStore
    @Binding private var parentIsRecording: Bool
    #if os(iOS)
        @State private var isSearchPresented = false
        @State private var transcriptSearchText = ""
    #endif

    private var memo: Memo { store.memo.wrappedValue }
    private var isRecording: Bool { store.state.isRecording }
    private var isPlaying: Bool { store.state.isPlaying }
    private var isGenerating: Bool { store.state.isGenerating }
    private var isProcessingSampleAudio: Bool { store.state.isProcessingSampleAudio }
    private var recordingDuration: TimeInterval { store.state.recordingDuration }
    private var downloadProgress: Double { store.state.downloadProgress }
    private var currentPlaybackTime: Double { store.state.currentPlaybackTime }
    private var showingEnhancedView: Bool { store.state.showingEnhancedView }
    private var showingSpeakerView: Bool { store.state.showingSpeakerView }

    init(memo: Binding<Memo>, isRecording: Binding<Bool>) {
        self._store = StateObject(wrappedValue: TranscriptStore(memo: memo))
        self._parentIsRecording = isRecording
    }

    var body: some View {
        transcriptSurface
            .task {
                await store.send(.onAppear(modelContext, settings))
            }
            .onChange(of: isRecording) { _, newValue in
                parentIsRecording = newValue
            }
            .onDisappear {
                Task {
                    await store.send(.onDisappear)
                }
            }
            .alert(
                "Enhancement Error",
                isPresented: Binding(
                    get: { store.state.enhancementError != nil },
                    set: { isPresented in
                        if !isPresented {
                            Task {
                                await store.send(.errorAlertDismissed)
                            }
                        }
                    }
                )
            ) {
                Button("OK") {
                    Task {
                        await store.send(.errorAlertDismissed)
                    }
                }
            } message: {
                if let error = store.state.enhancementError {
                    Text(error)
                }
            }
    }

    @ViewBuilder
    private var transcriptSurface: some View {
        #if os(iOS)
            mobileTranscriptSurface
        #elseif os(macOS)
            desktopTranscriptSurface
        #endif
    }

    #if os(macOS)
    private var desktopTranscriptSurface: some View {
        ZStack {
            VStack(spacing: 0) {
                // Main content
                Group {
                    if !memo.isDone {
                        liveRecordingView
                    } else {
                        if memo.summary != nil && showingEnhancedView {
                            enhancedView
                        } else if memo.hasSpeakerData && showingSpeakerView {
                            speakerView
                        } else {
                            playbackView
                        }
                    }
                }

                // Add padding at bottom for floating buttons
                #if os(iOS)
                    Spacer().frame(height: 100)
                #else
                    Spacer()
                #endif
            }
            #if os(macOS)
                .padding(20)
            #endif

            // Floating buttons at the bottom for iOS
            #if os(iOS)
                VStack {
                    Spacer()

                    bottomButtonBar
                }
                .ignoresSafeArea(.keyboard)
            #endif
        }
        .navigationTitle(memo.title)
        .toolbar {
            Group {
                // AI controls
                if memo.isDone {
                    // Enhance button
                    ToolbarItem {
                        enhanceButton
                    }

                    ToolbarItem {
                        exportMenu
                    }

                    if let exportedURL = store.state.exportedURL {
                        ToolbarItem {
                            ShareLink(item: exportedURL) {
                                Label("Share Export", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                    // View toggle buttons
                    if memo.summary != nil {
                        ToolbarItem {
                            viewToggleButton
                        }
                    }
                    
                    if memo.hasSpeakerData {
                        ToolbarItem {
                            speakerViewToggleButton
                        }
                    }
                }

                ToolbarSpacer(.fixed)

                // Recording control
                if !memo.isDone {
                    ToolbarItem {
                        recordButton
                    }
                }

                ToolbarSpacer(.fixed)

                // Playback control
                if memo.isDone {
                    ToolbarItem {
                        playButton
                    }
                }

                ToolbarSpacer(.fixed)
            }
        }
    }
    #endif

    #if os(iOS)
    private var mobileTranscriptSurface: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            mobilePrimaryContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    mobileTopBar
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    mobileBottomBar
                }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var mobilePrimaryContent: some View {
        if !memo.isDone {
            mobileLiveRecordingView
        } else if memo.summary != nil && showingEnhancedView {
            enhancedView
                .background(Color.black)
        } else if memo.hasSpeakerData && showingSpeakerView {
            speakerView
                .background(Color.black)
        } else {
            mobilePlaybackView
        }
    }

    private var mobileTopBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if !isRecording {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(isRecording ? 0.35 : 0.92))
                        .frame(width: 58, height: 58)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.045), lineWidth: 1)
                        )
                }
                .disabled(isRecording)
                .accessibilityLabel("Back")

                Text("Transcript")
                    .font(.system(size: 23, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                HStack(spacing: 17) {
                    Button {
                        handleViewModeButtonTap()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 23, weight: .medium))
                    }
                    .accessibilityLabel("Toggle transcript view")

                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            isSearchPresented.toggle()
                            if !isSearchPresented {
                                transcriptSearchText = ""
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 25, weight: .regular))
                    }
                    .accessibilityLabel("Search transcript")

                    mobileOverflowMenu
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 15)
                .frame(height: 58)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.045), lineWidth: 1)
                )
            }

            if isSearchPresented {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    TextField("Search", text: $transcriptSearchText)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    if !transcriptSearchText.isEmpty {
                        Button {
                            transcriptSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.black)
    }

    private var mobileOverflowMenu: some View {
        Menu {
            if memo.summary != nil {
                Button(showingEnhancedView ? "Show Transcript" : "Show Summary") {
                    Task {
                        await store.send(.summaryToggleTapped)
                    }
                }
            }

            if memo.hasSpeakerData {
                Button(showingSpeakerView ? "Show Transcript" : "Show Speakers") {
                    Task {
                        await store.send(.speakerToggleTapped)
                    }
                }
            }

            Button(memo.summary != nil ? "Re-summarize" : "Summarize") {
                handleAIEnhanceButtonTap()
            }
            .disabled(memo.text.characters.isEmpty || isGenerating)

            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) {
                        Task {
                            await store.send(.exportTapped(format))
                        }
                    }
                }
            }
            .disabled(memo.transcriptText.isEmpty && memo.text.characters.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
        }
        .accessibilityLabel("More")
    }

    private var mobilePlaybackView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                let blocks = visibleMobileTranscriptBlocks

                if blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("0:00")
                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.26))

                        Text(
                            transcriptSearchText.isEmpty
                                ? "No transcript yet."
                                : "No matching transcript text."
                        )
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(9)
                    }
                } else {
                    ForEach(blocks) { block in
                        mobileTranscriptBlock(block)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.black)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func mobileTranscriptBlock(_ block: MobileTranscriptBlock) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(formatShortTimestamp(block.timestamp))
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.26))

            Text(block.text)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineSpacing(9)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var mobileLiveRecordingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(formatShortTimestamp(recordingDuration))
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.26))

                if store.state.finalizedTranscript.utf8.isEmpty
                    && store.state.volatileTranscript.utf8.isEmpty
                {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: isProcessingSampleAudio ? "waveform" : "mic.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(isProcessingSampleAudio ? SpokenWordTranscriber.green : .red)
                            .symbolEffect(.pulse, isActive: isRecording)

                        Text(isProcessingSampleAudio ? "Processing audio..." : "Listening...")
                            .font(.system(size: 24, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))

                        Text(
                            isProcessingSampleAudio
                                ? "Transcribing the selected recording."
                                : "Start speaking into the microphone."
                        )
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                } else {
                    Text(store.state.finalizedTranscript + store.state.volatileTranscript)
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(9)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.black)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var mobileBottomBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.78), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 26)

            if memo.isDone {
                mobilePlayerBar
            } else {
                mobileRecordBar
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.96))
    }

    private var mobilePlayerBar: some View {
        HStack(spacing: 12) {
            Button {
                handlePlayButtonTap()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(memo.url == nil)
            .opacity(memo.url == nil ? 0.45 : 1)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            mobileWaveform
                .frame(maxWidth: .infinity)

            Text("1x")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Text("\(formatDuration(currentPlaybackTime))/\(formatDuration(memo.duration ?? 0))")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var mobileRecordBar: some View {
        Button {
            handleRecordingButtonTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: sampleOrRecordingButtonImage)
                    .font(.system(size: 22, weight: .bold))

                Text(sampleOrRecordingButtonTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                if isProcessingSampleAudio {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(formatDuration(recordingDuration))
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                isRecording ? Color.red.opacity(0.64) : Color.white.opacity(0.09),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessingSampleAudio)
    }

    private var mobileWaveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(mobileWaveformHeights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(index <= mobilePlaybackBarIndex ? Color.white.opacity(0.72) : Color.white.opacity(0.24))
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(height: 38)
        .accessibilityHidden(true)
    }
    #endif

    // MARK: - Bottom Button Bar for iOS

    #if os(iOS)
        @ViewBuilder
        private var bottomButtonBar: some View {
            HStack(spacing: 16) {
                // Recording/Stop button - always visible when recording
                if !memo.isDone {
                    recordButtonLarge
                } else {
                    // View toggle buttons
                    HStack(spacing: 12) {
                        if memo.summary != nil {
                            viewToggleButtonCompact
                        }
                        
                        if memo.hasSpeakerData {
                            speakerViewToggleButtonCompact
                        }
                    }

                    Spacer()

                    // AI enhance button
                    enhanceButtonCompact

                    exportMenuCompact
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }

        @ViewBuilder
        private var recordButtonLarge: some View {
            Button {
                handleRecordingButtonTap()
            } label: {
                HStack(spacing: 12) {
                    Label(
                        sampleOrRecordingButtonTitle,
                        systemImage: sampleOrRecordingButtonImage
                    )
                    .font(.headline)
                    .fontWeight(.semibold)

                    if isProcessingSampleAudio {
                        ProgressView()
                            .controlSize(.small)
                    } else if isRecording {
                        Text(formatDuration(recordingDuration))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
            }
            .buttonStyle(.glass)
            .controlSize(.extraLarge)
            .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))  // Green for start, red for stop
            .disabled(isProcessingSampleAudio)
        }

        @ViewBuilder
        private var viewToggleButtonCompact: some View {
            Button {
                Task {
                    await store.send(.summaryToggleTapped)
                }
            } label: {
                Label(
                    showingEnhancedView ? "Transcript" : "Summary",
                    systemImage: showingEnhancedView ? "doc.plaintext" : "sparkles"
                )
                .font(.body)
                .fontWeight(.medium)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(showingEnhancedView ? .gray : SpokenWordTranscriber.green)
        }
        
        @ViewBuilder
        private var speakerViewToggleButtonCompact: some View {
            Button {
                Task {
                    await store.send(.speakerToggleTapped)
                }
            } label: {
                Label(
                    showingSpeakerView ? "Transcript" : "Speakers",
                    systemImage: showingSpeakerView ? "doc.plaintext" : "person.2"
                )
                .font(.body)
                .fontWeight(.medium)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(showingSpeakerView ? .gray : .blue)
        }

        @ViewBuilder
        private var enhanceButtonCompact: some View {
            Button {
                handleAIEnhanceButtonTap()
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        memo.summary != nil ? "Re-summarize" : "Summarize with AI",
                        systemImage: memo.summary != nil ? "arrow.clockwise" : "sparkles"
                    )
                    .font(.body)
                    .fontWeight(.medium)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(SpokenWordTranscriber.green)
            .disabled(memo.text.characters.isEmpty || isGenerating)
        }
    #endif

    // MARK: - Enhanced View

    @ViewBuilder
    private var enhancedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
                // Simplified header for iOS
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(SpokenWordTranscriber.green)

                    Text("AI Summary")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            #endif

            #if os(macOS)
                // Header section with better spacing
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(SpokenWordTranscriber.green)
                            .symbolRenderingMode(.monochrome)

                        Text("AI Enhanced Summary")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            #endif

            // Enhanced content area with better formatting
            Group {
                if let summary = memo.summary, !String(summary.characters).isEmpty {
                    ScrollView {
                        Text(summary)
                            .font(.body)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            #if os(iOS)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            #else
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            #endif
                            .textSelection(.enabled)
                    }
                    #if os(macOS)
                        .padding(.horizontal, 16)
                    #endif
                    .scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    // Improved loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .foregroundStyle(SpokenWordTranscriber.green)

                        VStack(spacing: 8) {
                            Text("Generating enhanced summary...")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("This may take a moment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
            .background(.background.secondary.opacity(0.3))
        #endif
    }
    
    // MARK: - Speaker View
    
    @ViewBuilder
    private var speakerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
                // Simplified header for iOS
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.body)
                        .foregroundStyle(.blue)

                    Text("Speakers")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()
                    
                    // Speaker count badge
                    if memo.hasSpeakerData {
                        Text("\(memo.speakers(in: modelContext).count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            #endif

            #if os(macOS)
                // Header section with better spacing
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .symbolRenderingMode(.monochrome)

                        Text("Speaker Diarization")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()
                        
                        // Speaker count and processing info
                        if memo.hasSpeakerData {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(memo.speakers(in: modelContext).count) speakers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(memo.speakerSegments.count) segments")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            #endif

            // Speaker transcript content
            Group {
                if memo.hasSpeakerData {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Speaker legend
                            speakerLegend
                            
                            Divider()
                            
                            // Speaker-segmented transcript
                            Text(memo.formattedTranscriptWithSpeakers(context: modelContext))
                                .font(.body)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                #if os(iOS)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                #else
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                #endif
                                .textSelection(.enabled)
                        }
                    }
                    #if os(macOS)
                        .padding(.horizontal, 16)
                    #endif
                    .scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    // No speaker data state
                    VStack(spacing: 20) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            Text("No Speaker Data")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Speaker diarization was not performed for this recording")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
            .background(.background.secondary.opacity(0.3))
        #endif
    }
    
    @ViewBuilder
    private var speakerLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speakers")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            let speakers = memo.speakers(in: modelContext)
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120))
            ], spacing: 8) {
                ForEach(speakers, id: \.id) { speaker in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(speaker.displayColor)
                            .frame(width: 12, height: 12)
                        
                        Text(speaker.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Individual Toolbar Buttons

    @ViewBuilder
    private var playButton: some View {
        Button {
            handlePlayButtonTap()
        } label: {
            Label(
                isPlaying ? "Pause" : "Play",
                systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var recordButton: some View {
        Button {
            handleRecordingButtonTap()
        } label: {
            HStack(spacing: 8) {
                Label(
                    sampleOrRecordingButtonTitle,
                    systemImage: sampleOrRecordingButtonImage
                )

                if isProcessingSampleAudio {
                    ProgressView()
                        .controlSize(.small)
                } else if isRecording {
                    Text(formatDuration(recordingDuration))
                        .font(.body)
                        .monospacedDigit()
                }
            }
        }
        .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))
        .disabled(isProcessingSampleAudio)
    }

    @ViewBuilder
    private var viewToggleButton: some View {
        Button {
            Task {
                await store.send(.summaryToggleTapped)
            }
        } label: {
            Label(
                showingEnhancedView ? "Transcript" : "Summary",
                systemImage: showingEnhancedView
                    ? "doc.plaintext.fill" : "sparkles.rectangle.stack.fill"
            )
        }
        .buttonStyle(.glass)
    }
    
    @ViewBuilder
    private var speakerViewToggleButton: some View {
        Button {
            Task {
                await store.send(.speakerToggleTapped)
            }
        } label: {
            Label(
                showingSpeakerView ? "Transcript" : "Speakers",
                systemImage: showingSpeakerView ? "doc.plaintext.fill" : "person.2.fill"
            )
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var enhanceButton: some View {
        Button {
            handleAIEnhanceButtonTap()
        } label: {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    memo.summary != nil ? "Re-enhance" : "Enhance",
                    systemImage: memo.summary != nil ? "arrow.clockwise" : "sparkles"
                )
            }
        }
        .buttonStyle(.glass)
        .tint(SpokenWordTranscriber.green)
        .disabled(memo.text.characters.isEmpty || isGenerating)
    }

    @ViewBuilder
    var liveRecordingView: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if store.state.finalizedTranscript.utf8.isEmpty
                    && store.state.volatileTranscript.utf8.isEmpty
                {
                    VStack(spacing: 20) {
                        // Recording indicator with glass effect
                        VStack(spacing: 12) {
                            Image(systemName: isProcessingSampleAudio ? "waveform" : "mic.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(isProcessingSampleAudio ? SpokenWordTranscriber.green : .red)
                                .symbolEffect(.pulse, isActive: isRecording)

                            // Recording timer
                            Text(formatDuration(recordingDuration))
                                .font(.system(size: 32, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)

                            Text(isProcessingSampleAudio ? "Processing Sample..." : "Listening...")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text(
                                isProcessingSampleAudio
                                    ? "Transcribing sample.mp3"
                                    : "Start speaking into the microphone"
                            )
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 32)
                        .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(iOS)
                        .padding(.top, 40)
                    #else
                        .padding()
                    #endif
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        // Live transcript with glass container
                        Text(
                            store.state.finalizedTranscript
                                + store.state.volatileTranscript
                        )
                        .font(.body)
                        .lineSpacing(4)
                        #if os(iOS)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        #else
                            .padding(20)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder
    var playbackView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                #if os(macOS)
                    Text("Transcript")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                #endif

                transcriptStatusView

                Text(memo.textBrokenUpByParagraphs())
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    #else
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    #endif
                    .textSelection(.enabled)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder
    private var transcriptStatusView: some View {
        HStack(spacing: 8) {
            Label(memo.resolvedTranscriptionStatus.displayName, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)

            if memo.resolvedTranscriptionStatus == .transcribing || memo.resolvedTranscriptionStatus == .preparing {
                ProgressView(value: memo.transcriptionProgress)
                    .frame(maxWidth: 120)
            }

            if let exportedURL = store.state.exportedURL {
                ShareLink(item: exportedURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
            }
        }
        #if os(iOS)
            .padding(.horizontal, 16)
        #else
            .padding(.horizontal, 12)
        #endif
    }

    private var statusIcon: String {
        switch memo.resolvedTranscriptionStatus {
        case .pending:
            return "clock"
        case .recording:
            return "mic.fill"
        case .preparing:
            return "gearshape"
        case .transcribing:
            return "waveform"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch memo.resolvedTranscriptionStatus {
        case .completed:
            return .green
        case .failed, .cancelled:
            return .red
        case .recording, .preparing, .transcribing:
            return .blue
        case .pending:
            return .secondary
        }
    }

    @ViewBuilder
    private var exportMenu: some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    Task {
                        await store.send(.exportTapped(format))
                    }
                } label: {
                    Text(format.displayName)
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(memo.transcriptText.isEmpty && memo.text.characters.isEmpty)
    }

    @ViewBuilder
    private var exportMenuCompact: some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    Task {
                        await store.send(.exportTapped(format))
                    }
                } label: {
                    Text(format.displayName)
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.body)
                .fontWeight(.medium)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(memo.transcriptText.isEmpty && memo.text.characters.isEmpty)
    }

    private var progressView: some View {
        ProgressView(value: downloadProgress, total: 100)
            .progressViewStyle(LinearProgressViewStyle())
            .opacity(downloadProgress > 0 && downloadProgress < 100 ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: downloadProgress)
    }
}

#if os(iOS)
private struct MobileTranscriptBlock: Identifiable {
    let id: String
    let timestamp: TimeInterval
    let text: String
}
#endif

// MARK: - TranscriptView Extension

extension TranscriptView {

    // Format duration for display
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    #if os(iOS)
    private var mobileWaveformHeights: [CGFloat] {
        [13, 25, 18, 31, 16, 37, 22, 29, 14, 34, 19, 40, 24, 32, 17, 36, 21, 30, 15, 35, 20, 38, 23, 31, 18, 28, 14, 33, 19, 27]
    }

    private var mobilePlaybackBarIndex: Int {
        guard let duration = memo.duration, duration > 0 else { return -1 }
        let progress = min(max(currentPlaybackTime / duration, 0), 1)
        return Int(progress * Double(max(mobileWaveformHeights.count - 1, 0)))
    }

    private var visibleMobileTranscriptBlocks: [MobileTranscriptBlock] {
        let blocks = mobileTranscriptBlocks
        let query = transcriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return blocks }

        return blocks.filter { block in
            block.text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    private var mobileTranscriptBlocks: [MobileTranscriptBlock] {
        let segments = memo.transcriptSegments
            .sorted { $0.startTime < $1.startTime }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !segments.isEmpty {
            return segments.map { segment in
                MobileTranscriptBlock(
                    id: segment.id,
                    timestamp: segment.startTime,
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }

        let chunks = mobileTextChunks(from: mobileTranscriptText)
        guard !chunks.isEmpty else { return [] }

        let duration = memo.duration ?? Double(max(chunks.count, 1)) * 10
        let interval = duration / Double(max(chunks.count, 1))

        return chunks.enumerated().map { index, chunk in
            MobileTranscriptBlock(
                id: "\(index)-\(chunk.hashValue)",
                timestamp: Double(index) * interval,
                text: chunk
            )
        }
    }

    private var mobileTranscriptText: String {
        let transcript = memo.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            return transcript
        }

        let text = String(memo.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }

        return memo.cleanedTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func mobileTextChunks(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count > 1 {
            return paragraphs
        }

        var chunks: [String] = []
        var currentSentences: [String] = []
        var currentCharacterCount = 0

        trimmed.enumerateSubstrings(
            in: trimmed.startIndex..<trimmed.endIndex,
            options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            guard let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sentence.isEmpty
            else {
                return
            }

            currentSentences.append(sentence)
            currentCharacterCount += sentence.count

            if currentSentences.count >= 3 || currentCharacterCount > 260 {
                chunks.append(currentSentences.joined(separator: " "))
                currentSentences.removeAll()
                currentCharacterCount = 0
            }
        }

        if !currentSentences.isEmpty {
            chunks.append(currentSentences.joined(separator: " "))
        }

        return chunks.isEmpty ? [trimmed] : chunks
    }

    private func formatShortTimestamp(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }

    private func handleViewModeButtonTap() {
        if memo.summary != nil {
            Task {
                await store.send(.summaryToggleTapped)
            }
        } else if memo.hasSpeakerData {
            Task {
                await store.send(.speakerToggleTapped)
            }
        }
    }
    #endif

    private var sampleOrRecordingButtonTitle: String {
        if isProcessingSampleAudio {
            return "Processing Sample"
        }

        return isRecording ? "Stop Recording" : "Start Recording"
    }

    private var sampleOrRecordingButtonImage: String {
        if isProcessingSampleAudio {
            return "waveform"
        }

        return isRecording ? "stop.circle.fill" : "record.circle.fill"
    }

    func handleRecordingButtonTap() {
        Task {
            await store.send(.recordingButtonTapped)
        }
    }

    func handlePlayButtonTap() {
        Task {
            await store.send(.playButtonTapped)
        }
    }

    func handleAIEnhanceButtonTap() {
        Task {
            await store.send(.aiEnhanceButtonTapped)
        }
    }

    @ViewBuilder func textScrollView(attributedString: AttributedString) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                textWithHighlighting(attributedString: attributedString)
                Spacer()
            }
        }
    }

    func attributedStringWithCurrentValueHighlighted(attributedString: AttributedString)
        -> AttributedString
    {
        var copy = attributedString
        copy.runs.forEach { run in
            if shouldBeHighlighted(attributedStringRun: run) {
                let range = run.range
                copy[range].backgroundColor = .mint.opacity(0.2)
            }
        }
        return copy
    }

    func shouldBeHighlighted(attributedStringRun: AttributedString.Runs.Run) -> Bool {
        guard isPlaying else { return false }
        let start = attributedStringRun.audioTimeRange?.start.seconds
        let end = attributedStringRun.audioTimeRange?.end.seconds
        guard let start, let end else {
            return false
        }

        if end < currentPlaybackTime { return false }

        if start < currentPlaybackTime, currentPlaybackTime < end {
            return true
        }

        return false
    }

    @ViewBuilder func textWithHighlighting(attributedString: AttributedString) -> some View {
        Group {
            Text(attributedStringWithCurrentValueHighlighted(attributedString: attributedString))
                .font(.body)
        }
    }
}
