# Changelog

## 1.0.0

- Rebuilt the desktop application with Swift 6 and SwiftUI.
- Added native SQLite persistence compatible with the original database schema.
- Added immutable Prompt versions, history browsing, search, tags, and text Diff.
- Added JSON and Markdown `PVM-DATA-V1` import/export compatibility.
- Serialized concurrent version writes with SQLite transactions.
- Added Unicode-aware tag identity and legacy duplicate consolidation.
- Added a native arm64 macOS 13+ application bundle.
