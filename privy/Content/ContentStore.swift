import CasePaths
import Combine
import Dependencies
import Foundation
import SwiftData

@MainActor
final class ContentStore: ObservableObject {
    @Published var state: State

    @Dependency(\.audioImportClient)
    private var audioImportClient

    init(initialState: State = .init()) {
        self.state = initialState
    }

    func send(_ action: Action) async {
        CoreLogger.info(action.description)

        switch action {
        case let .selectionChanged(memo):
            state.selection = memo
            if let memo {
                state.currentMemo = memo
            }

        case let .currentMemoChanged(memo):
            state.currentMemo = memo

        case .addMemo(let modelContext):
            let newMemo = Memo.blank()
            modelContext.insert(newMemo)
            state.selection = newMemo
            state.currentMemo = newMemo

        case let .deleteMemo(memo, modelContext):
            if state.selection === memo {
                state.selection = nil
            }
            modelContext.delete(memo)

        case let .deleteMemos(offsets, memos, modelContext):
            for index in offsets {
                let memo = memos[index]
                if state.selection === memo {
                    state.selection = nil
                }
                modelContext.delete(memo)
            }

        case let .recordingChanged(isRecording):
            state.isRecording = isRecording

        case .settingsTapped:
            state.destination = .settings

        case .settingsDismissed:
            state.destination = nil

        case let .importMedia(url, modelContext):
            do {
                let importedAudio = try await audioImportClient.importMedia(url)
                let memo = Memo.imported(importedAudio)
                modelContext.insert(memo)
                state.selection = memo
                state.currentMemo = memo
                state.importError = nil
            } catch {
                state.importError = error.localizedDescription
            }

        case .importErrorDismissed:
            state.importError = nil

        case let .importFailed(message):
            state.importError = message
        }
    }
}

extension ContentStore {
    struct State: Equatable {
        var selection: Memo?
        var currentMemo = Memo.blank()
        var isRecording = false
        var importError: String?
        var destination: Destination?

        @CasePathable
        enum Destination: Equatable {
            case settings
        }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.selection?.persistentModelID == rhs.selection?.persistentModelID
                && lhs.currentMemo.persistentModelID == rhs.currentMemo.persistentModelID
                && lhs.isRecording == rhs.isRecording
                && lhs.importError == rhs.importError
                && lhs.destination == rhs.destination
        }
    }

    enum Action {
        case selectionChanged(Memo?)
        case currentMemoChanged(Memo)
        case addMemo(ModelContext)
        case deleteMemo(Memo, ModelContext)
        case deleteMemos(IndexSet, [Memo], ModelContext)
        case recordingChanged(Bool)
        case settingsTapped
        case settingsDismissed
        case importMedia(URL, ModelContext)
        case importFailed(String)
        case importErrorDismissed

        var description: String {
            switch self {
            case .selectionChanged:
                return "selectionChanged"
            case .currentMemoChanged:
                return "currentMemoChanged"
            case .addMemo:
                return "addMemo"
            case .deleteMemo:
                return "deleteMemo"
            case .deleteMemos:
                return "deleteMemos"
            case .recordingChanged:
                return "recordingChanged"
            case .settingsTapped:
                return "settingsTapped"
            case .settingsDismissed:
                return "settingsDismissed"
            case .importMedia:
                return "importMedia"
            case .importErrorDismissed:
                return "importErrorDismissed"
            case .importFailed:
                return "importFailed"
            }
        }
    }
}
