# Codex task ledger prototype

The menu bar includes a manual Codex task log. Start a record before work, then finish it with the retry count and a verification result. Each record can include a title, project or repository, issue or pull request, model, reasoning effort, and test notes. Elapsed time is wall-clock time between the two actions; it includes idle time and sleep.

The widget currently receives an account-wide cumulative token counter and account quota windows. Neither source identifies the active task or session. Task records therefore leave `attributedSessionTokens` empty. At task start and finish, the app saves account quota and token-counter observations in a separate `account-observations.json` file. The task record links to those snapshots and may show the account-level change during the period, clearly marked as unattributed. It can also note if a fresh quota snapshot first showed a window at 100% while the task was active; this does not prove that the window caused an interruption. The app never labels account-level changes as task consumption or converts them into a cost.

Use **Task history…** to review recent records and **Export task ledger…** to save a JSON bundle containing tasks and their separate account observations. Task fields and validation notes are user-entered. Files stay on the Mac unless the user explicitly exports them. The app keeps at most 5,000 task records and 10,000 task-boundary account snapshots.

## Long-term usage event ledger

The widget also keeps a separate append-only `usage-events.jsonl` file and a small `usage-event-state.json` checkpoint. It writes a full account observation on the first successful sample and at least every 15 minutes while polling, then immediately records detected data gaps, account changes, resets, source corrections, window disappearance/return, and source failures or recovery. Comparable same-account checkpoints show the observed quota/token-counter change; gaps, account switches, resets, and corrections break that comparison baseline. The state file updates on each successful poll so a restart can distinguish an actual observation gap from a sparse event log. The menu shows the latest 30 events; **Export usage events…** copies the complete JSON Lines stream. When the active log reaches 20 MB it is archived as `usage-events-<UTC time>.jsonl` and a new log starts; archives are included in the export. Nothing expires or is deleted automatically.

A successful quota sample more than five minutes after the previous one creates a gap event. An account switch starts a new comparison segment; the ledger does not compare balances across accounts. A window decrease is classified as a reset when its reset boundary changes materially or the prior boundary has passed. A decrease without an observed reset boundary is labeled a source correction or regression. Token-counter decreases use the same correction label. These are classifications from observed snapshots; they cannot prove why the remote value changed or recover events that happened entirely between polls. Ordinary checkpoints and account-token totals remain account-wide and are never task consumption.

## Why this prototype

Recent Reddit reports describe two practical problems: tasks stopping when a short quota window is exhausted, and account limits changing in ways users cannot reconcile with their visible token graph. These posts are anecdotes, not proof of a provider-side defect. A local task timeline can help users compare work periods with account snapshots and record whether the task passed, failed, or was interrupted, without claiming causal attribution:

- [5-hour limit and unfinished tasks](https://www.reddit.com/r/codex/comments/1vy3yhu/5_hour_limits_are_back_for_plus_users/)
- [Unexpected changes in quota consumption](https://www.reddit.com/r/codex/comments/1wc4aqe/limits_are_absolutely_destroyed/)
- [Quota decrease reported without a visible task](https://www.reddit.com/r/codex/comments/1uglj9f/codex_usage_dropped_without_running_any_tasks/)

CodexBar already offers deeper session, model, and project cost analysis in its [Codex usage documentation](https://github.com/steipete/CodexBar/blob/main/docs/codex.md). This prototype explores a different record: developer-entered task boundaries and verification outcomes, with account-wide observations kept distinct. It is not a claim that CodexBar cannot add the same workflow.

## Source diagnostics

**Source diagnostics…** reports freshness from each source's last successful sample, alongside the last attempt, last success, age threshold, retry state, and error code. Codex quota and account-token sources are independent. Optional bridge diagnostics describe the local snapshot file the widget reads; they do not prove that the provider's remote service is healthy.
