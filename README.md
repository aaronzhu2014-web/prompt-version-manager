# Prompt Version Manager

A local-first, native macOS application for keeping an immutable history of prompts.

Prompt Version Manager is built with Swift 6, SwiftUI, and the system SQLite library. It has no third-party runtime dependencies, accounts, telemetry, network requests, or API keys.

## Features

- Create prompts with descriptions, tags, model names, ratings, and notes.
- Save every content change as a new immutable version.
- Open and inspect any historical version.
- Search titles, descriptions, tags, and all historical content.
- Filter by tag with Unicode-aware case-insensitive identity.
- Compare any two versions with a line-oriented Diff.
- Import and export complete history as JSON or readable Markdown.
- Use an existing Prompt Version Manager SQLite database without conversion.

## Requirements

- macOS 13 or later
- Apple Silicon for the prebuilt v1.0.1 release

## Install

Download `Prompt-Version-Manager-v1.0.1-macos-arm64.zip` from the GitHub Releases page, unzip it, and move `Prompt Version Manager.app` to Applications.

The release uses local ad-hoc signing rather than an Apple Developer ID. Depending on macOS security settings, the first launch may require Control-clicking the app and choosing Open.

## Build from source

Install Xcode or Apple Command Line Tools, then run:

```bash
./scripts/build_macos_app.sh
```

The generated application is:

```text
Prompt Version Manager.app
```

Create a distributable ZIP:

```bash
./scripts/package_release.sh 1.0.1
```

Run the Swift core checks:

```bash
./scripts/check_swift.sh
```

## Run with a specific database

```bash
"./Prompt Version Manager.app/Contents/MacOS/prompt-version-manager" \
  --db ./example.db
```

The default database location follows this order:

1. `PROMPTVM_DB`
2. `$XDG_DATA_HOME/promptvm/promptvm.db`
3. `~/.local/share/promptvm/promptvm.db`

## Data and privacy

All Prompt data stays in the selected SQLite file. The application never sends Prompt content anywhere.

JSON and Markdown exports contain the complete history and metadata of a Prompt. Treat exported files as private data when the Prompt itself is sensitive.

## Compatibility

The application uses the original four-table SQLite schema:

```text
prompts ──< versions
   │
   └──< prompt_tags >── tags
```

JSON and Markdown use format version 1:

```text
format = prompt-version-manager
format_version = 1
Markdown marker = PVM-DATA-V1
```

Imports always receive a new local UUID and never overwrite an existing Prompt.

## Project structure

```text
Sources/
├── PromptVersionCore/        Models, SQLite, Diff, and interchange
├── PromptVersionManager/     Native SwiftUI desktop application
└── PromptVersionCoreChecks/  Dependency-free executable checks

Packaging/                    macOS bundle metadata
Assets/                       Application icon source and macOS icon bundle
scripts/                      Build, check, and release packaging
examples/                     Synthetic import example
```

## License

MIT
