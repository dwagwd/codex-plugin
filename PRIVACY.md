# Privacy and data handling

The widget asks a local Codex App Server for account identity, quota windows, and the reported cumulative account token counter. Codex may make authenticated requests to OpenAI to answer these queries. Codex's own configuration and data policies continue to apply.

The widget does not read conversation contents, session logs, prompts, or authentication files. It does not start model turns, redeem reset credits, send telemetry to a separate service, or upload local samples.

## Stored locally

In `~/Library/Application Support/CodexUsageWidget/`:

- `history.json`: quota samples and a hashed account identifier.
- `tokens.json`: cumulative token samples and a hashed account identifier.
- `status.json`: current widget diagnostics, selected plan/window, and operational settings.
- `instance.lock`: prevents duplicate processes.

Language, observation duration, rate unit, position, and collapse/pin preferences are stored in the app's defaults domain. Account email/id is used in memory to derive an identifier; raw credentials are never persisted by the widget.

Histories are trimmed to a 31-day horizon when samples are collected. Resets, counter corrections, plan/account changes, or gaps over 5 minutes can clear the affected observation segment earlier. If the widget is stopped or offline, existing files remain until collection resumes or the user removes them.

To delete collected data, quit the widget and remove its Application Support directory. Preferences can be removed separately using the macOS defaults domain `local.codex.usage-widget`.

Local files and screenshots may disclose usage patterns. Share only redacted diagnostics. Public source archives deliberately exclude local state, credentials, and profiling output.

## Optional provider integrations

Claude Code and Antigravity CLI bridges receive official status-line JSON, normalize quota fields, and discard the raw payload. Only hashed session/account identity, observation time, and quotas are saved locally. Existing status-line commands are preserved; setup creates a local settings backup. The native widget reads changed snapshots every 15 seconds only when imports are enabled. Bridge history is kept in process memory.

The optional Cursor Teams collector sends an exact member-email filter to the official Cursor Team Admin API. Its admin key is entered in a terminal without echo and kept only in process memory. The key is never stored in a file, preference, command-line argument, model conversation, or log. No redirects are followed. The collector must be started manually and stopped with Ctrl-C. It does not retrieve browser cookies. Normalized snapshots contain no email or credentials.

The repository and packages exclude runtime snapshots and settings backups. Optional bridge removal instructions are in [providers.md](docs/providers.md).
