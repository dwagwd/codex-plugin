# Release checklist

## Local preparation

- Run `./scripts/check.sh` and `./scripts/package.sh` on macOS.
- Keep `VERSION`, the base version of `.codex-plugin/plugin.json`, and `CHANGELOG.md` aligned.
- Inspect both ZIPs. The source exporter includes only public source/documentation directories and strips local Codex cachebuster suffixes.
- App ZIP names include the architecture of the build machine. Do not describe a single-architecture package as universal.
- Exercise language settings, invalid/valid intervals, both rate units, account/plan changes, restart, and unsupported-token behavior.
- Keep remaining limitations documented in `docs/validation.md`.

## Before first public launch

- The public source repository is `dwagwd/codex-plugin`. Publishing a release requires maintainer authorization, a tested commit, and reviewed release assets.
- Enable GitHub private vulnerability reporting and configure branch protection after CI is available.
- Verify GitHub Actions on the chosen repository; local validation does not mean hosted CI has passed.
- Review the license, project description, screenshots, and source archive for personal data.
- The first public release is source-only. Do not upload the locally built ad-hoc-signed App ZIP as a ready-to-install release asset. Apple signing/notarization and download-install testing are prerequisites for official prebuilt binaries.

## Publication

The `Package artifacts` workflow is manual and only uploads build artifacts. It does not publish a GitHub release, create tags, or push source. Create version tags/releases only when the maintainer explicitly chooses to publish. Do not embed local marketplace paths in public instructions.

No public repository, remote, tag, or release is created by the build scripts.
