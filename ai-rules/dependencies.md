# Required Dependencies

## Core Point-Free Libraries

Add these to your `Package.swift` or Xcode project:

```swift
dependencies: [
    // Core Point-Free libraries (REQUIRED)
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.7.0"),

    // Optional but recommended
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.7.0"),
]
```

## Target Dependencies

In your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
        .product(name: "CasePaths", package: "swift-case-paths"),
    ]
)
```

## Library Purposes

- **swift-dependencies**: Dependency injection system
- **swift-navigation**: Type-safe navigation with @CasePathable
- **swift-case-paths**: Enum case path support
- **swift-perception**: Fine-grained observation (optional)
- **swift-concurrency-extras**: Concurrency helpers (optional)
- **swift-custom-dump**: Better debug output (optional)
- **xctest-dynamic-overlay**: Testing utilities (optional)

## Minimum Required

For this architecture to work, you MUST have:
1. ✅ `swift-dependencies`
2. ✅ `swift-navigation`
3. ✅ `swift-case-paths`

The rest are optional enhancements.
