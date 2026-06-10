# Quick Start Template

## Minimal Feature Implementation

Copy this template to start a new feature:

```swift
// 1. Create Store File: FeatureStore.swift
import SwiftUI
import Dependencies
import SwiftUINavigation

@MainActor
class FeatureStore: ObservableObject {
    @Published var state: State

    @Dependency(\.yourClient)
    var yourClient

    init(initialState: State = .init()) {
        self.state = initialState
    }

    func send(_ action: Action) async {
        switch action {
        case .onAppear:
            // Initialize feature
            break

        case .buttonTapped:
            // Handle button tap
            state.someProperty = "new value"

        case .loadData:
            // Load data from client
            do {
                let result = try await yourClient.fetchData()
                state.data = result
            } catch {
                state.error = error
            }
        }
    }
}

extension FeatureStore {
    struct State: Equatable {
        var someProperty: String = ""
        var data: [Item] = []
        var error: Error?
        var destination: Destination?

        @CasePathable
        enum Destination: Equatable {
            case detail(DetailStore.State)
            case settings
        }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.someProperty == rhs.someProperty &&
            lhs.data == rhs.data &&
            lhs.destination == rhs.destination
            // Note: Exclude error from Equatable if needed
        }
    }

    enum Action {
        case onAppear
        case buttonTapped
        case loadData

        var description: String {
            switch self {
            case .onAppear: return "onAppear"
            case .buttonTapped: return "buttonTapped"
            case .loadData: return "loadData"
            }
        }
    }
}

// 2. Create View File: FeatureView.swift
struct FeatureView: View {
    @StateObject var store: FeatureStore

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Feature")
                .task {
                    await store.send(.onAppear)
                }
                .sheet(item: $store.state.destination.detail) { detailState in
                    NavigationStack {
                        DetailView(store: .init(initialState: detailState))
                    }
                }
        }
    }

    private var content: some View {
        VStack {
            Text(store.state.someProperty)

            Button("Tap Me") {
                Task { await store.send(.buttonTapped) }
            }
        }
    }
}

// 3. Initialize in parent
struct ParentView: View {
    var body: some View {
        FeatureView(store: .init())
    }
}
```

## With Navigation

```swift
// Child navigation
.sheet(item: $store.state.destination.detail) { childState in
    NavigationStack {
        DetailView(store: .init(initialState: childState))
    }
}

// Simple sheet
.sheet(isPresented: Binding($store.state.destination.settings)) {
    SettingsView()
}

// Navigation push
.navigationDestination(item: $store.state.destination.detail) { childState in
    DetailView(store: .init(initialState: childState))
}

// Full screen
.fullScreenCover(isPresented: Binding($store.state.destination.fullScreen)) {
    FullScreenView()
}
```

## With Dependencies

```swift
// 1. Create Client: YourClient.swift
import Dependencies

struct YourClient {
    var fetchData: @Sendable () async throws -> [Item]
    var saveData: @Sendable ([Item]) async throws -> Void

    static var live: Self {
        Self(
            fetchData: {
                // Real API call
                try await URLSession.shared.data(from: url)
            },
            saveData: { items in
                // Real save operation
            }
        )
    }

    static var preview: Self {
        Self(
            fetchData: {
                // Return mock data
                return [Item.mock, Item.mock]
            },
            saveData: { _ in
                // No-op
            }
        )
    }
}

extension YourClient: DependencyKey {
    static var liveValue = live
    static let previewValue = preview
}

extension DependencyValues {
    var yourClient: YourClient {
        get { self[YourClient.self] }
        set { self[YourClient.self] = newValue }
    }
}

// 2. Use in Store
@MainActor
class FeatureStore: ObservableObject {
    @Dependency(\.yourClient)
    var yourClient

    func send(_ action: Action) async {
        switch action {
        case .loadData:
            do {
                let data = try await yourClient.fetchData()
                state.data = data
            } catch {
                state.error = error
            }
        }
    }
}
```

## With SwiftData

```swift
// 1. Define Model
import SwiftData

@Model
final class Item: Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdDate: Date = Date()

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

// 2. Use in View
struct FeatureView: View {
    @StateObject var store: FeatureStore

    @Query(sort: [.init(\Item.createdDate, order: .reverse)])
    private var items: [Item]

    @Environment(\.modelContext)
    private var context

    var body: some View {
        List(items) { item in
            Text(item.name)
        }
        .toolbar {
            Button("Add") {
                let newItem = Item(name: "New")
                context.insert(newItem)
            }
        }
    }
}
```

## Preview Setup

```swift
#Preview {
    FeatureView(store: .init())
}

// With initial state
#Preview {
    FeatureView(
        store: .init(
            initialState: .init(
                someProperty: "Preview value"
            )
        )
    )
}

// With SwiftData
#Preview {
    let container = try! ModelContainer(
        for: Item.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return FeatureView(store: .init())
        .modelContainer(container)
}
```
