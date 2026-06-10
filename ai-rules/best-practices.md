# Best Practices & Rules

## State Management

1. **Never mutate state in views** - Only in store's `send()` method
2. **Use computed properties** - Don't duplicate state
3. **Keep state flat** - Avoid deep nesting
4. **Make state Equatable** - Enable efficient SwiftUI updates
5. **Single source of truth** - State only lives in stores

## Navigation

1. **State-driven navigation** - All navigation through `destination`
2. **Type-safe** - Use `@CasePathable` enums
3. **Dismiss by setting to nil** - `state.destination = nil`
4. **Pass child state** - Use `.detail(ChildStore.State)` pattern
5. **Wrap in NavigationStack** - When child needs navigation

## Dependency Injection

1. **Struct over protocol** - Use struct-based clients
2. **Mark Sendable** - All closures `@Sendable`
3. **Provide implementations** - `live`, `preview`, `test`
4. **Use @Dependency** - In stores, not views
5. **No singletons** - Always inject dependencies

## Async/Await

1. **MainActor stores** - Mark all stores `@MainActor`
2. **Async send** - `func send(_ action: Action) async`
3. **Use Task** - For concurrent operations
4. **Handle cancellation** - Check `Task.isCancelled`
5. **Try/catch** - Always handle errors

## Testing

1. **Test stores** - Create with initial state, send actions, assert state
2. **Mock dependencies** - Use `preview` or custom test implementations
3. **No view tests** - Test stores instead
4. **Synchronous tests** - Use `await store.send()`
5. **Test one action at a time** - Clear test scenarios

## Code Style

1. **Action logging** - Always log actions with description
2. **Clear naming** - `buttonTapped` not `tap`
3. **Group related state** - Logical grouping
4. **Minimal computed properties** - Only for derived state
5. **Comments on complex logic** - Explain "why" not "what"

## Performance

1. **Equatable conformance** - Minimize view updates
2. **@Query in views** - For reactive SwiftData
3. **Lazy loading** - Load data when needed
4. **Debounce user input** - Prevent excessive updates
5. **Task cancellation** - Cancel ongoing work when dismissed

## Error Handling

1. **Catch all errors** - Never let errors crash
2. **Store errors in state** - `var error: Error?`
3. **Show user feedback** - Alert or inline message
4. **Log errors** - Use logger for debugging
5. **Retry logic** - When appropriate

## Concurrency

1. **One send() at a time** - Serialize actions
2. **Use Task.sleep** - For delays
3. **withTaskCancellation** - Handle cancellation
4. **AsyncStream** - For long-running operations
5. **Actor isolation** - Respect MainActor

## SwiftUI Integration

1. **@StateObject for root** - Main feature entry
2. **Pass stores down** - Constructor injection
3. **.task modifier** - For onAppear-like work
4. **Bindings from store** - Use Binding() wrapper
5. **Prefer .sheet(item:)** - Over .sheet(isPresented:)
