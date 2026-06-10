import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @StateObject private var store = ContentStore()
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
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
                    #if os(iOS)
                        // Keep only settings and edit buttons in toolbar
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            if !memos.isEmpty {
                                EditButton()
                            }

                            Button {
                                Task {
                                    await store.send(.settingsTapped)
                                }
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }
                    #elseif os(macOS)
                        // On macOS, settings are in the app menu, so only show the Add button
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

                #if os(iOS)
                    // Floating New button at the bottom for iOS
                    if !store.state.isRecording {
                        VStack {
                            Spacer()

                            Button {
                                Task {
                                    await store.send(.addMemo(modelContext))
                                }
                            } label: {
                                Label("New", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.extraLarge)
                            .tint(Color(red: 0.36, green: 0.69, blue: 0.55))  // Using the app's green color
                            .padding(.bottom, 24)
                        }
                    }
                #endif
            }
        } detail: {
            if store.state.selection != nil {
                TranscriptView(memo: currentMemoBinding, isRecording: isRecordingBinding)
            } else {
                Text("Select an item")
            }
        }
        #if os(iOS)
            .sheet(isPresented: settingsBinding) {
                SettingsView(settings: settings)
            }
        #endif
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
