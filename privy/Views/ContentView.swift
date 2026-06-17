import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @StateObject private var store = ContentStore()
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var isImporterPresented = false

    var body: some View {
        rootContent
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio, .movie],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    Task {
                        await store.send(.importMedia(url, modelContext))
                    }
                } else if case let .failure(error) = result {
                    Task {
                        await store.send(.importFailed(error.localizedDescription))
                    }
                }
            }
            .alert(
                "Import Failed",
                isPresented: Binding(
                    get: { store.state.importError != nil },
                    set: { isPresented in
                        if !isPresented {
                            Task {
                                await store.send(.importErrorDismissed)
                            }
                        }
                    }
                )
            ) {
                Button("OK") {
                    Task {
                        await store.send(.importErrorDismissed)
                    }
                }
            } message: {
                if let importError = store.state.importError {
                    Text(importError)
                }
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(iOS)
            NavigationStack {
                mobileMemoList
                    .navigationDestination(item: selectionBinding) { _ in
                        TranscriptView(memo: currentMemoBinding, isRecording: isRecordingBinding)
                    }
            }
            .sheet(isPresented: settingsBinding) {
                SettingsView(settings: settings)
            }
        #elseif os(macOS)
        NavigationSplitView {
            sidebar
        } detail: {
            if store.state.selection != nil {
                TranscriptView(memo: currentMemoBinding, isRecording: isRecordingBinding)
            } else {
                Text("Select an item")
            }
        }
        #endif
    }

    @ViewBuilder
    private var sidebar: some View {
        #if os(iOS)
            mobileMemoList
        #elseif os(macOS)
            desktopMemoList
        #endif
    }

    #if os(iOS)
        private var mobileMemoList: some View {
            ZStack(alignment: .bottom) {
                Color.black
                    .ignoresSafeArea()

                List(selection: selectionBinding) {
                    ForEach(memos) { memo in
                        Button {
                            Task {
                                await store.send(.selectionChanged(memo))
                            }
                        } label: {
                            MemoCardView(memo: memo)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: 28, bottom: 7, trailing: 28))
                        .listRowBackground(Color.black)
                    }
                    .onDelete { offsets in
                        Task {
                            await store.send(.deleteMemos(offsets, memos, modelContext))
                        }
                    }

                    Color.clear
                        .frame(height: 112)
                        .listRowInsets(.init())
                        .listRowBackground(Color.black)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .navigationTitle("")
                .toolbar(.hidden, for: .navigationBar)

                if !store.state.isRecording {
                    mobileCaptureDock
                }
            }
        }

        private var mobileCaptureDock: some View {
            HStack(spacing: 22) {
                Spacer()

                Button {
                    Task {
                        await store.send(.addMemo(modelContext))
                    }
                } label: {
                    Circle()
                        .fill(Color(white: 0.9))
                        .frame(width: 82, height: 82)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: 7)
                        )
                        .shadow(color: .black.opacity(0.48), radius: 18, y: 8)
                }
                .accessibilityLabel("New memo")

                Button {
                    isImporterPresented = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(Color(white: 0.1), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.38), radius: 12, y: 7)
                }
                .accessibilityLabel("Import media")

                Spacer()
                    .frame(width: 48)
            }
            .padding(.bottom, 18)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.86), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .offset(y: 24),
                alignment: .bottom
            )
        }
    #endif

    private var desktopMemoList: some View {
        ZStack {
            List(selection: selectionBinding) {
                ForEach(memos) { memo in
                    NavigationLink(value: memo) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(memo.title))
                                .font(.headline)
                            Text(memo.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !memo.text.characters.isEmpty {
                                Text(
                                    String(memo.text.characters.prefix(50))
                                        + (memo.text.characters.count > 50 ? "..." : "")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    Task {
                        await store.send(.deleteMemos(offsets, memos, modelContext))
                    }
                }
            }
            .navigationTitle("Memos")
            .navigationSplitViewColumnWidth(min: 250, ideal: 250, max: 400)
            .toolbar {
                #if os(macOS)
                    ToolbarItemGroup(placement: .primaryAction) {
                        if !memos.isEmpty && store.state.selection != nil {
                            Button {
                                if let selection = store.state.selection {
                                    Task {
                                        await store.send(.deleteMemo(selection, modelContext))
                                    }
                                }
                            } label: {
                                Label("Delete Memo", systemImage: "trash")
                            }
                            .foregroundColor(.red)
                        }

                        if !store.state.isRecording {
                            Button {
                                isImporterPresented = true
                            } label: {
                                Label("Import Media", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                Task {
                                    await store.send(.addMemo(modelContext))
                                }
                            } label: {
                                Label("New Memo", systemImage: "plus")
                            }
                        }
                    }
                #endif
            }
            .toolbarBackground(.hidden)
        }
    }

    private var selectionBinding: Binding<Memo?> {
        Binding(
            get: { store.state.selection },
            set: { newValue in
                Task {
                    await store.send(.selectionChanged(newValue))
                }
            }
        )
    }

    private var currentMemoBinding: Binding<Memo> {
        Binding(
            get: { store.state.currentMemo },
            set: { newValue in
                Task {
                    await store.send(.currentMemoChanged(newValue))
                }
            }
        )
    }

    private var isRecordingBinding: Binding<Bool> {
        Binding(
            get: { store.state.isRecording },
            set: { newValue in
                Task {
                    await store.send(.recordingChanged(newValue))
                }
            }
        )
    }

    private var settingsBinding: Binding<Bool> {
        Binding(
            get: { store.state.destination == .settings },
            set: { isPresented in
                if !isPresented {
                    Task {
                        await store.send(.settingsDismissed)
                    }
                }
            }
        )
    }
}

#if os(iOS)
    private struct MemoCardView: View {
        let memo: Memo

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedDate)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.43))

                    Spacer()

                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.58))
                        .accessibilityHidden(true)
                }

                Text(previewText)
                    .font(.system(size: 25, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(7)
                    .lineLimit(3)
                    .minimumScaleFactor(0.86)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Spacer()

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Color(red: 0.19, green: 0.78, blue: 0.54))

                    Text(formattedDuration)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 24)
            .frame(minHeight: 222)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(white: 0.065))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.025), lineWidth: 1)
            )
        }

        private var previewText: String {
            let cleaned = memo.cleanedTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cleaned.isEmpty {
                return cleaned
            }

            let transcript = memo.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                return transcript
            }

            let text = String(memo.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }

            return memo.title == "New Memo" ? "Ready for a new recording." : memo.title
        }

        private var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy, HH:mm"
            return formatter.string(from: memo.createdAt)
        }

        private var formattedDuration: String {
            let duration = max(0, Int((memo.duration ?? 0).rounded()))
            let minutes = duration / 60
            let seconds = duration % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
#endif
