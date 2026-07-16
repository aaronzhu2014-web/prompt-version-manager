# Architecture

Prompt Version Manager is separated into three Swift Package Manager targets:

- `PromptVersionCore`: models, SQLite transactions, search, tags, Diff, and import/export.
- `PromptVersionManager`: the SwiftUI macOS application.
- `PromptVersionCoreChecks`: dependency-free executable integration checks.

## Compatibility choices

- The existing SQLite schema is retained instead of migrating to SwiftData or Core Data.
- Timestamps remain UTC ISO-8601 strings.
- JSON and Markdown retain `prompt-version-manager` format version 1.
- Markdown retains the URL-safe Base64 `PVM-DATA-V1` marker.
- The default database remains under `~/.local/share/promptvm`.

## Reliability

Version allocation is performed inside `BEGIN IMMEDIATE` transactions, preventing simultaneous writers from selecting the same next version number. Unicode-equivalent duplicate tags are consolidated when a repository opens.
