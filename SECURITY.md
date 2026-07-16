# Security

Prompt Version Manager is local-first and does not make network requests, use accounts, collect telemetry, or require API keys.

## Reporting a vulnerability

Please open a GitHub security advisory for vulnerabilities that could expose local Prompt contents, overwrite history, or execute imported data. Avoid including real private Prompt data in reports; use a minimal synthetic example instead.

## Data handling

- Prompt data remains in the SQLite file selected by the user.
- Imported JSON and Markdown are treated as data and are never executed.
- Export files may contain the complete Prompt history and should be handled as sensitive user data.
