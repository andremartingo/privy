# File Organization Rules

## Rule: Feature Folder Structure

```
FeatureName/
├── FeatureView.swift        # SwiftUI view
├── FeatureStore.swift       # State management
└── SupportingViews.swift    # Child views (optional)
```

## Rule: Project Structure

```
ProjectName/
├── Model/                   # SwiftData models
│   ├── Entity1.swift
│   └── Entity2.swift
├── Clients/                 # Dependency implementations
│   ├── NetworkClient.swift
│   └── StorageClient.swift
├── Feature1/                # Feature modules
│   ├── Feature1View.swift
│   └── Feature1Store.swift
├── Feature2/
│   ├── Feature2View.swift
│   └── Feature2Store.swift
├── Shared/                  # Shared components
│   └── ReusableView.swift
├── Utilities/               # Utilities
│   ├── Logger.swift
│   └── Extensions.swift
└── AppName.swift           # App entry point
```

## Naming Conventions

- **Stores**: `FeatureStore` (e.g., `HomeStore`, `ProfileStore`)
- **Views**: `FeatureView` (e.g., `HomeView`, `ProfileView`)
- **Clients**: `FeatureClient` (e.g., `NetworkClient`, `StorageClient`)
- **Models**: `EntityName` (e.g., `User`, `Product`)

## File Location Rules

1. **One store per file** - `FeatureStore.swift`
2. **One main view per file** - `FeatureView.swift`
3. **Group by feature** - Not by type
4. **Shared code** - In `Shared/` or `Utilities/`
5. **Models separate** - In `Model/` directory
6. **Clients separate** - In `Clients/` directory

## Anti-Patterns

❌ **Don't group by type**
```
Views/
  HomeView.swift
  ProfileView.swift
Stores/
  HomeStore.swift
  ProfileStore.swift
```

✅ **Do group by feature**
```
Home/
  HomeView.swift
  HomeStore.swift
Profile/
  ProfileView.swift
  ProfileStore.swift
```
