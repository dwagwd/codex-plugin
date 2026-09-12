# Contributing

Contributions are licensed under the repository's MIT license. No CLA is required.

1. Build on macOS with Swift 5.9+ and Python 3 available.
2. Run `./scripts/check.sh` and `./scripts/build.sh`.
3. For UI changes, test the settings window, all three explicit languages, expanded/collapsed layouts, and persistence after reopening.
4. Describe behavior changes, test evidence, and any untested platform cases in your pull request.

## Structure

- `UsageCore`: quota/token history, observation settings, localization, geometry.
- `UsageTransport`: read-only Codex App Server protocol and subprocess lifecycle.
- `UsageWidget`: AppKit card, menu bar, settings window, local persistence.

Preserve the distinction between account tokens and selected plan quota. Do not invent per-model attribution or fixed token-to-quota multipliers. New data collection requires corresponding privacy documentation. Keep authentication in Codex and use synthetic protocol fixtures for tests.

Add translations for every key in `Localization.swift`. Keep existing saved data decodable or add explicit migrations. Tests should cover changed behavior and failure paths, not merely repeat implementation details.

Never commit credentials, observed usage histories, real account identifiers, local build products, or machine-specific paths. The release exporter uses an explicit file allowlist; update it when adding public files.
