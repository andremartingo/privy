# Architecture Guide - View → Store Pattern

> This project uses a **View → Store** architecture with Point-Free's libraries for state management, navigation, and dependency injection.

## 📚 Rule Index

Each topic has its own detailed rule file. Click to navigate:

### Core Architecture
- **[Store Pattern](ai-rules/store-pattern.md)** - View → Store architecture, State, Actions, send() method
- **[Navigation](ai-rules/navigation.md)** - SwiftUINavigation, @CasePathable, Destination enum, sheet/push patterns
- **[Dependency Injection](ai-rules/dependency-injection.md)** - Swift Dependencies, Client pattern, @Dependency usage

### Data & Organization
- **[Data Persistence](ai-rules/data-persistence.md)** - SwiftData models, @Query, @Relationship, ModelContext
- **[File Organization](ai-rules/file-organization.md)** - Project structure, feature folders, naming conventions

### Guidelines
- **[Best Practices](ai-rules/best-practices.md)** - State management, async/await, testing, performance tips
- **[Anti-Patterns](ai-rules/anti-patterns.md)** - Common mistakes to avoid with explanations

### Getting Started
- **[Dependencies](ai-rules/dependencies.md)** - Required Swift packages from Point-Free
- **[Quick Start](ai-rules/quick-start.md)** - Copy-paste templates for new features

## 🎯 Architecture Overview

```
View → Action → Store → State → View
```

1. **Views** render UI and dispatch actions
2. **Actions** describe user intentions (enums)
3. **Stores** handle business logic and update state
4. **State** flows unidirectionally back to views

## 🚀 Quick Reference

### Create a Feature

1. Create `FeatureStore.swift` with State, Action, send()
2. Create `FeatureView.swift` that observes the store
3. Use `@CasePathable` Destination enum for navigation
4. Inject dependencies via `@Dependency`

### Navigate to Another Screen

```swift
// In Store
state.destination = .detail(DetailStore.State())

// In View
.sheet(item: $store.state.destination.detail) { childState in
    DetailView(store: .init(initialState: childState))
}
```

### Create a Client Dependency

```swift
struct FeatureClient {
    var operation: @Sendable () async throws -> Result

    static var live: Self { /* real implementation */ }
    static var preview: Self { /* mock implementation */ }
}

extension FeatureClient: DependencyKey {
    static var liveValue = live
    static let previewValue = preview
}
```

## 📖 When to Use Each Rule

| If you're... | Read this rule |
|-------------|----------------|
| Creating a new feature | [Quick Start](ai-rules/quick-start.md) |
| Setting up navigation | [Navigation](ai-rules/navigation.md) |
| Managing state | [Store Pattern](ai-rules/store-pattern.md) |
| Adding external dependencies | [Dependency Injection](ai-rules/dependency-injection.md) |
| Working with data models | [Data Persistence](ai-rules/data-persistence.md) |
| Organizing files | [File Organization](ai-rules/file-organization.md) |
| Stuck on something | [Anti-Patterns](ai-rules/anti-patterns.md) |
| Optimizing code | [Best Practices](ai-rules/best-practices.md) |

## ✅ Checklist for New Features

- [ ] Store follows pattern: `@MainActor`, `@Published var state`, `func send(_ action: Action) async`
- [ ] State has `Destination` enum with `@CasePathable`
- [ ] Actions have `var description: String` for logging
- [ ] Dependencies use struct-based clients with `live` and `preview`
- [ ] Navigation uses SwiftUINavigation (`.sheet(item:)`, `.navigationDestination`)
- [ ] File organization: `FeatureName/FeatureView.swift` + `FeatureName/FeatureStore.swift`
- [ ] No anti-patterns: no `@StateObject` in children, no direct state mutation, no singletons

## 🎓 Learning Path

**Beginner**: Start here
1. [Quick Start](ai-rules/quick-start.md) - Copy template
2. [Store Pattern](ai-rules/store-pattern.md) - Understand the basics
3. [Navigation](ai-rules/navigation.md) - Add screens

**Intermediate**: Level up
4. [Dependency Injection](ai-rules/dependency-injection.md) - Manage dependencies
5. [Data Persistence](ai-rules/data-persistence.md) - Work with SwiftData
6. [Best Practices](ai-rules/best-practices.md) - Write better code

**Advanced**: Mastery
7. [Anti-Patterns](ai-rules/anti-patterns.md) - Avoid pitfalls
8. [File Organization](ai-rules/file-organization.md) - Scale the codebase

## 🔗 External Resources

- [Point-Free Swift Navigation](https://github.com/pointfreeco/swift-navigation)
- [Point-Free Swift Dependencies](https://github.com/pointfreeco/swift-dependencies)
- [Apple SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)

---

**Remember**: These rules exist to create consistent, maintainable, and testable code. Follow them strictly for best results.
