# Project Context

`quickreview.nvim` annotates native Neovim quickfix and location-list items.
Notes live in `item.user_data.quickreview`; native list data remains the
source of truth.

## Dependencies

- Neovim 0.10+
- Required: [quickfix-actions.nvim](https://github.com/leolaurindo/quickfix-actions.nvim)
- Required: [quickfix-export.nvim](https://github.com/leolaurindo/quickfix-export.nvim)
- Optional: [quickfix-persist.nvim](https://github.com/leolaurindo/quickfix-persist.nvim)

Local development uses sibling checkouts under `~/projects`; keep those paths
and `test/manual_init.lua` working until the plugins are published.

## Decisions

- Use Lua modules for plugin integration; commands are user-facing wrappers.
- Preserve producer fields, text, metadata, and native qf rendering.
- Do not own `quickfixtextfunc`, parse rendered qf text, or implement qf `:write`.
- Keep persistence note-agnostic and optional.

## Coding Style

- Prefer small, direct Lua changes and existing Neovim APIs.
- Keep generic list/export behavior in the sibling plugins.
- Add focused headless tests for behavior changes and run `luacheck`.
