# Data Persistence Rules (SwiftData)

## Rule: Model Definition

```swift
@Model
final class EntityName: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var property: String
    var date: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Parent.children)
    var parent: Parent?

    @Relationship(deleteRule: .cascade, inverse: \Child.parent)
    var children: [Child]?

    init(property: String) {
        self.id = UUID()
        self.property = property
    }
}
```

**Requirements:**
- ✅ Marked with `@Model`
- ✅ `final class`
- ✅ Conform to `Identifiable, Hashable, Sendable`
- ✅ Use `@Relationship` for relationships
- ✅ Specify `deleteRule` (`.nullify`, `.cascade`, `.deny`)
- ✅ Define inverse relationships

## Rule: Data Access in Views

```swift
struct FeatureView: View {
    @Query(sort: [.init(\Model.createdDate, order: .reverse)])
    private var items: [Model]

    @Environment(\.modelContext)
    private var context

    var body: some View {
        List(items) { item in
            // Use items
        }
    }
}
```

**Requirements:**
- ✅ Use `@Query` for reactive data fetching
- ✅ Inject `modelContext` via `@Environment`
- ✅ Define sort descriptors
- ✅ Use predicates for filtering when needed

## Rule: ModelContext in Stores

When stores need to access SwiftData:

```swift
extension FeatureStore {
    struct State: Equatable {
        var modelContext: ModelContext? = nil

        static func == (lhs: State, rhs: State) -> Bool {
            // Exclude modelContext from equality
            return lhs.id == rhs.id
        }
    }
}

// Pass from view
FeatureView(store: .init(initialState: .init(modelContext: context)))
```

## Rule: Model Container Setup

```swift
var sharedModelContainer: ModelContainer = {
    let schema = Schema([
        Entity1.self,
        Entity2.self,
    ])

    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        cloudKitDatabase: .automatic
    )

    return try! ModelContainer(for: schema, configurations: [modelConfiguration])
}()
```

## SwiftData Best Practices

1. **Use @Query in views** - For reactive data
2. **Pass context to stores** - When needed
3. **Define relationships** - Use `@Relationship` macro
4. **Specify delete rules** - `.nullify`, `.cascade`, or `.deny`
5. **Use predicates** - For filtering queries

## Required Import

```swift
import SwiftData
```
