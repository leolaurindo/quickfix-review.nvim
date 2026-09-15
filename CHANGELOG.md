# Changelog

All notable changes to Quickfix Review are documented here.

## Unreleased

## [0.2.0] - 2026-09-15

### Added

- One-off Sidekick submission, including a send-and-clear variant, for ephemeral review attention points.
- A default-on, consumed agent-response mailbox with opt-out configuration, best-effort local Git exclusion, and atomic-write handling.
- Agent-note clearing and default export filtering with explicit opt-in inclusion.
- Theme-aware Nerd Font pencil and robot indicators, with portable fallbacks, for user and agent notes.
- Range-endpoint indicators and persistent `:QuickfixReviewHoverAll` overlays that follow visible source endpoints while scrolling.

### Changed

- Avoid redundant persistence writes after restoring the review list and unnecessary branch lookups for repository and custom scopes.
- Restrict the bundled agent skill to explicit Quickfix Review requests.
- Show automatic range hover only at endpoints while allowing explicit hover from any line inside a range.

## [0.1.0] - 2026-09-09

Initial public release.

### Added

- Notes anchored to source buffers, quickfix entries, location-list entries, and Git diff rows.
- A scoped, owned `Quickfix Review` quickfix list for reviewing, persisting, and exporting notes.
- Line-specific, range, and file-level notes with stale-source detection and re-anchoring.
- Native quickfix mappings: `<CR>` jumps, `dd` deletes, and `a`/`i` add or edit notes.
- Agent findings import through versioned JSON and `:QuickfixReviewImport`.
- Agent provenance metadata and filtered `:QuickfixReviewExportUser` / `:QuickfixReviewExportAgent` commands.
- Markdown, JSON, clipboard, file, and optional Sidekick export integrations.
- Optional persistence through `quickfix-persist.nvim` and Git diff metadata through `quickfix-diffs.nvim`.
- Resolver integrations for native diffs, Diffview, CodeDiff, Differ, diffs.nvim, and Neogit.

### Configuration

- Global mappings are disabled by default to avoid collisions.
- Quickfix Actions and Export are required; Persist and Diffs are optional.
- Neovim 0.10 or newer is required.

[Unreleased]: https://github.com/leolaurindo/quickfix-review.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/leolaurindo/quickfix-review.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/leolaurindo/quickfix-review.nvim/releases/tag/v0.1.0
