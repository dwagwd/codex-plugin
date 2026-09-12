# Security policy

Security fixes target the latest source release. This project is a local companion and does not host a service.

Report suspected vulnerabilities through the repository's **private vulnerability reporting** channel when enabled. If no private channel is available, open a minimal issue asking the maintainer for a private contact method; do not include exploitation details, credentials, or user data in the public issue.

Useful private reports include affected version, macOS/Codex versions, impact, and a reproducible case using synthetic data.

Maintainers should enable private vulnerability reporting before public launch. The widget uses the existing Codex authentication context, stores usage samples locally, and exposes no listening network server. Review changes to subprocess arguments, persistence, release packaging, and data export carefully.
