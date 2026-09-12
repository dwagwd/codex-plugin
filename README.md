# Codex Usage Widget

A small, native macOS desktop widget for **plan quota**, **account token consumption**, and **reset countdowns**. Built with AppKit and Swift, without a browser runtime or model-turn polling.

[繁體中文](README.zh-TW.md) · [Privacy](PRIVACY.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)

Unofficial community project. Not affiliated with or endorsed by OpenAI, Anthropic, Google, or Cursor. Product names belong to their respective owners.

## Features

- Draggable 260 × 128 pt card; collapsible 182 × 32 pt capsule, with a settings gear in both modes.
- Separate plan-quota and Codex account token rates. Compact `%/h` notation means percentage points per hour (20% → 25% in one hour = 5%/h).
- Keep one selected quota or add up to four additional quotas. The card grows vertically; collapse returns to one compact capsule.
- Custom text/background RGB values (0–255) or automatic system appearance.
- Energy saver: 120-second network polling and 15-second display updates. Hidden cards stop the UI timer; rate calculations are cached until new samples arrive.
- Optional Claude Code and Antigravity CLI status-line bridges; Cursor Teams on-demand spend-cap collector. [Provider support and setup](docs/providers.md)
- Observation window: **1 minute to 30 days**, entered as a whole number of minutes, hours, or days.
- Independent rate display unit: per minute, hour, or day.
- English, Traditional/Simplified Chinese, Japanese, Korean, Spanish, French, German, Brazilian Portuguese, Italian, or follow the system language. Translations are included for all interface keys; native-speaker review is welcome.
- Actual backend quota windows and plan names, including distinct model buckets when available.
- Local sample history, saved position/settings, stale-data indicators, automatic reconnection, and manual startup.

## Build and install

Requirements: macOS 13+, Swift 5.9+ / Xcode Command Line Tools, Python 3 for tests and packaging, and Codex desktop or CLI signed in with a ChatGPT account. The core Codex app is native and does not require Python; optional provider bridges use Python 3.

Download the source ZIP from [Releases](https://github.com/dwagwd/codex-plugin/releases/latest), extract it, and open a terminal in the extracted `codex-usage-widget` folder. Or clone the repository:

```sh
git clone https://github.com/dwagwd/codex-plugin.git codex-usage-widget
cd codex-usage-widget
```

Then build and launch:

```sh
./scripts/check.sh
./scripts/build-install.sh
./scripts/launch.sh
```

The app is installed at `~/Applications/Codex Usage Widget.app`. Reopening it reveals the existing instance. It does not enable login startup. Use the menu bar item to hide/show, refresh, pin, or quit.

Click the **gear** to configure language, observation window, rate units, additional quotas, RGB colors, energy saving, and provider imports, then **Apply**. Click the card title to select a quota window. Drag blank space to move the card. Hover over each rate for its source and actual observed duration.

A Codex plugin manifest and launch skill are included. See [Codex plugin setup](docs/plugin.md).

## What the numbers mean

| Metric | Source | Calculation and scope |
|---|---|---|
| Plan quota | `account/rateLimits/read` | Observed percentage-point increase in the selected quota window. The displayed plan is backend-reported. |
| Account tokens | `account/usage/read` → `summary.lifetimeTokens` | Observed increase in the account-wide reported cumulative token counter. This is not a per-model measurement. |
| Reset countdown | `resetsAt` | Time until the backend-provided reset; reaching zero does not assume the reset occurred. |

**Tokens are not converted into quota using fixed multipliers.** Models and plans can consume quota differently. Shared quota buckets do not expose attribution to each model, so the widget reports actual bucket changes and does not label them as one model's usage. A distinct Spark bucket is separate from the main shared Codex bucket.

Rates are estimates: differences are divided by elapsed observation time, including idle time, and scaled to the selected display unit. “Per day” scales the observed pace; it is not a promise of future consumption. The footer shows the requested observation window, and tooltips show each metric's actual observed duration.

The default is the latest hour, shown per hour. Warmup requires the shorter of 5 minutes or the requested window. Shorter-than-requested observations are labeled estimates. No historical samples are invented when extending the window. Counters can update late; zero token rate means no reported increase, not proof of zero model activity.

Quota resets, decreases, plan changes, account switches, clock reversal, or gaps over 5 minutes restart the affected observation segment. Token counter corrections and account switches similarly restart token observation. Up to 31 days of samples are kept while collecting; stopped or offline installations retain their last files until collection resumes or the files are removed. An interrupted multi-day session therefore does not produce a continuous multi-day rate.

Missing or unsupported token data shows `—` while quota continues to work. API-key-only accounts may not expose these ChatGPT usage endpoints. Codex authentication stays with Codex; the widget never reads or copies authentication files or starts model turns.

## Development and packaging

```sh
./scripts/check.sh     # Swift tests + source export hygiene
./scripts/build.sh     # Build/sign locally, without installing
./scripts/package.sh   # Architecture-specific app ZIP + portable source ZIP
```

Builds use `~/Library/Caches/CodexUsageWidget/` by default. Override `CODEX_WIDGET_BUILD_CACHE`, `CODEX_WIDGET_TEST_CACHE`, or `CODEX_WIDGET_DIST_DIR` as needed. `CODEX_USAGE_CODEX_PATH` selects a custom Codex executable when launching the native executable directly.

Packages use ad-hoc signing and are **not notarized**. Source builds are the supported installation path for this version. A manual GitHub Actions packaging workflow creates downloadable artifacts; it does not publish releases. [Release checklist](docs/releasing.md)

## Local data and removal

Samples and diagnostic snapshots are stored in `~/Library/Application Support/CodexUsageWidget/`. Preferences use the `local.codex.usage-widget` defaults domain. Avoid uploading these files or unredacted screenshots to public issues.

To remove: quit the widget, remove its app, optionally remove its local data and preferences, and remove the plugin from Codex if installed. No daemon or login item is installed.

## Status

Version 0.3.1 is the first public **source release**, under MIT. Codex is the live-tested provider. Optional Claude/Antigravity/Cursor bridges are experimental and fixture-tested; see their support boundaries before setup. Published releases include a source ZIP and SHA-256 checksums. Prebuilt unnotarized apps are not attached to the public release; build locally using the steps above. CI tests and builds on macOS 14 and 15. See [validation scope](docs/validation.md) for local checks and limitations.
