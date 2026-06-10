# Store Pattern Rules

## Core Architecture: View → Store Pattern

```swift
View → Action → Store → State → View
```

- Views dispatch actions
- Stores handle actions and update state
- State flows down to views
- No direct state mutation in views

## Rule: Store Structure

Every feature store MUST follow this structure:

```swift
@MainActor
class FeatureStore: ObservableObject {
    @Published var state: State

    @Dependency(\.clientName)
    var clientName

    init(initialState: State = .init()) {
        self.state = initialState
    }

    func send(_ action: Action) async {
        CoreLogger.info(action.description)
        switch action {
        case .someAction:
            // Handle action
            state.someProperty = newValue
        }
    }
}
```

**Requirements:**
- ✅ Marked with `@MainActor`
- ✅ Conforms to `ObservableObject`
- ✅ Single `@Published var state: State`
- ✅ Dependencies injected via `@Dependency`
- ✅ Single `func send(_ action: Action) async` method
- ✅ Log all actions with `CoreLogger.info(action.description)`

## Rule: State Definition

States MUST be defined as nested structs:

```swift
extension FeatureStore {
    struct State: Equatable {
        // Data properties
        var someProperty: String = ""
        var isLoading: Bool = false

        // Navigation state
        var destination: Destination?

        // Computed properties for derived state
        var isValid: Bool {
            !someProperty.isEmpty
        }

        @CasePathable
        enum Destination: Equatable {
            case detail(DetailStore.State)  // Pass child state
            case sheet                      // Simple presentation
            case fullScreenCover            // Modal presentation
        }
    }
}
```

**Requirements:**
- ✅ Nested inside store extension
- ✅ Conform to `Equatable`
- ✅ Use `@CasePathable` for `Destination` enum
- ✅ Include `destination` property for navigation
- ✅ Use computed properties for derived state (never duplicate state)
- ✅ Default values for all properties

## Rule: Action Definition

Actions MUST be enums with description:

```swift
extension FeatureStore {
    enum Action {
        case onAppear
        case buttonTapped
        case updateValue(String)
        case childAction(ChildType)

        var description: String {
            switch self {
            case .onAppear:
                return "onAppear"
            case .buttonTapped:
                return "buttonTapped"
            case .updateValue:
                return "updateValue"
            case .childAction:
                return "childAction"
            }
        }
    }
}
```

**Requirements:**
- ✅ Nested inside store extension
- ✅ Enum with associated values for data
- ✅ Always include `var description: String` for logging
- ✅ Use present tense for actions (e.g., `buttonTapped`, not `buttonTap`)

## State Management Best Practices

1. **Never mutate state in views** - Only in store's `send()` method
2. **Use computed properties** - Don't duplicate state
3. **Keep state flat** - Avoid deep nesting
4. **Make state Equatable** - Enable efficient SwiftUI updates
5. **Single source of truth** - State only lives in stores
