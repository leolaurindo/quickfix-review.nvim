# Development notes

Quickfix Review adds notes from source buffers, quickfix/location-list rows, and
Git diff rows. Its goal is to keep notes available anywhere a native
quickfix/location-list can carry a location. Each note is stored in
`item.user_data.quickfix_review`, mirrored into the owned notes quickfix list, and
kept alongside canonical native data.

- Depend only on the standalone sibling plugins composing [`quickfix-kit.nvim`](https://github.com/leolaurindo/quickfix-kit.nvim):
    - [`quickfix-actions.nvim`](https://github.com/leolaurindo/quickfix-actions.nvim) provides native list access and mutation;
    - [`quickfix-export.nvim`](https://github.com/leolaurindo/quickfix-export.nvim) formats and sends records;
    - [`quickfix-persist.nvim`](https://github.com/leolaurindo/quickfix-persist.nvim) provides optional snapshots;
    - [`quickfix-diffs.nvim`](https://github.com/leolaurindo/quickfix-diffs.nvim) provides optional Git diff lists and metadata.

- Currently, Actions and Export are required; Persist and Diffs are optional. Use their Lua APIs, never `quickfix-kit.nvim` itself or command wrappers.
- Preserve producer fields, text, metadata, and native rendering.
- Keep quickfix/location-list buffers native and read-only; don't parse rendered
  rows, don't own `quickfixtextfunc`, and don't persist producer lists automatically.
- Keep sibling checkouts and `test/manual_init.lua` working during local development.
- Before handoff, run `make test`; it includes the Lua tests and skill frontmatter check. If it fails, fix the issue and run `make test` again.
