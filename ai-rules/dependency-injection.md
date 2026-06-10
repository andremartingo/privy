# Dependency Injection Rules (Swift Dependencies)

## Rule: Client Pattern

All external dependencies MUST be defined as struct-based clients:

```swift
struct FeatureClient {
    var someOperation: @Sendable () async throws -> Result
    var anotherOperation: @Sendable (Input) async -> Output

    static var live: Self {
        Self(
            someOperation: {
                // Real implementation
            },
            anotherOperation: { input in
                // Real implementation
            }
        )
    }

    static var preview: Self {
        Self(
            someOperation: {
                // Preview/mock data
            },
            anotherOperation: { _ in
                // Preview/mock data
            }
        )
    }
}

extension FeatureClient: DependencyKey {
    static var liveValue = live
    static let previewValue = preview
}

extension DependencyValues {
    var featureClient: FeatureClient {
        get { self[FeatureClient.self] }
        set { self[FeatureClient.self] = newValue }
    }
}
```

**Requirements:**
- ✅ Struct (not protocol)
- ✅ All closures marked `@Sendable`
- ✅ Provide `live` implementation
- ✅ Provide `preview` implementation
- ✅ Conform to `DependencyKey`
- ✅ Extend `DependencyValues` with accessor

## Rule: Using Dependencies in Stores

```swift
@MainActor
class FeatureStore: ObservableObject {
    @Dependency(\.featureClient)
    var featureClient

    @Dependency(\.anotherClient)
    var anotherClient

    func send(_ action: Action) async {
        switch action {
        case .loadData:
            do {
                let result = try await featureClient.someOperation()
                state.data = result
            } catch {
                state.error = error
            }
        }
    }
}
```

## Rule: Common Client Types to Create

Create clients for:
- **Network operations**: API calls, GraphQL queries
- **Storage operations**: UserDefaults, Keychain, File system
- **External services**: Analytics, Crash reporting, Push notifications
- **Platform APIs**: Location, Camera, Photo library
- **Business logic**: Complex calculations, validations

## Dependency Injection Best Practices

1. **Struct over protocol** - Use struct-based clients
2. **Mark Sendable** - All closures `@Sendable`
3. **Provide implementations** - `live`, `preview`, `test`
4. **Use @Dependency** - In stores, not views
5. **No singletons** - Always inject dependencies

## Required Import

```swift
import Dependencies
```

## Anti-Patterns

❌ **Don't create dependencies as classes**
```swift
// BAD
class NetworkManager { }

// GOOD
struct NetworkClient { }
```

❌ **Don't use protocols for dependencies**
```swift
// BAD
protocol NetworkService { }

// GOOD
struct NetworkClient { }
```
