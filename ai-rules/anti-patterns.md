# Anti-Patterns to Avoid

## ❌ Don't use @StateObject in child views

```swift
// BAD
ChildView(item: item)
    @StateObject var store = FeatureStore()

// GOOD
ChildView(store: .init(initialState: .init(item: item)))
```

**Why**: Creates new store instance, loses parent control

## ❌ Don't use @Binding for state management

```swift
// BAD
ChildView(text: $text)

// GOOD - Pass action instead
ChildView(text: text, onChange: { await store.send(.textChanged($0)) })
```

**Why**: Breaks unidirectional data flow

## ❌ Don't create dependencies as classes

```swift
// BAD
class NetworkManager { }

// GOOD
struct NetworkClient { }
```

**Why**: Structs are value types, easier to test, no shared state

## ❌ Don't use protocols for dependencies

```swift
// BAD
protocol NetworkService { }

// GOOD
struct NetworkClient { }
```

**Why**: Protocol + mock = more boilerplate, structs are simpler

## ❌ Don't mutate state outside send()

```swift
// BAD
Button("Tap") {
    store.state.count += 1
}

// GOOD
Button("Tap") {
    Task { await store.send(.incrementTapped) }
}
```

**Why**: Bypasses action logging, breaks debugging

## ❌ Don't duplicate state

```swift
// BAD
struct State {
    var firstName: String
    var lastName: String
    var fullName: String  // Duplicates data
}

// GOOD
struct State {
    var firstName: String
    var lastName: String
    var fullName: String { "\(firstName) \(lastName)" }
}
```

**Why**: Creates sync issues, harder to maintain

## ❌ Don't use deep state nesting

```swift
// BAD
struct State {
    var user: User?
    var userSettings: UserSettings?
    var userProfile: UserProfile?
}

// GOOD
struct State {
    var user: UserData  // Flattened
}
```

**Why**: Harder to update, more Equatable checks

## ❌ Don't skip action descriptions

```swift
// BAD
enum Action {
    case buttonTapped
    // No description property
}

// GOOD
enum Action {
    case buttonTapped

    var description: String {
        switch self {
        case .buttonTapped: return "buttonTapped"
        }
    }
}
```

**Why**: Loses debugging/logging capability

## ❌ Don't use navigation without Destination enum

```swift
// BAD
@State private var showDetail = false

// GOOD
@CasePathable
enum Destination {
    case detail
}
var destination: Destination?
```

**Why**: Loses type safety, harder to test

## ❌ Don't inject dependencies in views

```swift
// BAD
struct FeatureView: View {
    @Dependency(\.networkClient) var networkClient
}

// GOOD - Inject in stores only
class FeatureStore: ObservableObject {
    @Dependency(\.networkClient) var networkClient
}
```

**Why**: Views should be dumb, stores handle logic

## ❌ Don't create store singletons

```swift
// BAD
class FeatureStore {
    static let shared = FeatureStore()
}

// GOOD
// Create new instances
FeatureView(store: .init())
```

**Why**: Hard to test, shared mutable state
