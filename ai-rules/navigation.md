# Navigation Rules (SwiftUINavigation)

## Rule: Navigation via Destination Enum

All navigation MUST be handled through the `Destination` enum:

```swift
@CasePathable
enum Destination: Equatable {
    case detail(ChildStore.State)   // For stateful children
    case sheet                       // For simple sheets
    case fullScreen                  // For full screen covers
    case push(Model)                // For navigation stack
}

var destination: Destination?
```

**To navigate**: Set `state.destination = .someCase`
**To dismiss**: Set `state.destination = nil`

## Rule: Sheet Presentation

```swift
.sheet(item: $store.state.destination.detail) { childState in
    NavigationStack {
        ChildView(store: .init(initialState: childState))
    }
}
```

**Pattern:**
- Use `.sheet(item:)` for case with associated value
- Use `.sheet(isPresented: Binding($store.state.destination.sheet))` for simple cases
- Wrap in `NavigationStack` if child needs navigation

## Rule: Full Screen Covers

```swift
.fullScreenCover(isPresented: Binding($store.state.destination.fullScreen)) {
    FullScreenView()
}
```

## Rule: Navigation Stack Push

```swift
.navigationDestination(item: $store.state.destination.push) { model in
    DetailView(model: model)
}
```

## Rule: Boolean-Based Navigation

```swift
// In State
@CasePathable
enum Destination: Equatable {
    case settings
}

// In View
.sheet(isPresented: Binding($store.state.destination.settings)) {
    SettingsView()
}
```

## Navigation Best Practices

1. **State-driven navigation** - All navigation through `destination`
2. **Type-safe** - Use `@CasePathable` enums
3. **Dismiss by setting to nil** - `state.destination = nil`
4. **Pass child state** - Use `.detail(ChildStore.State)` pattern
5. **Wrap in NavigationStack** - When child needs navigation

## Required Import

```swift
import SwiftUINavigation
```
