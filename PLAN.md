# QuickReview Plan

The current runtime uses native quickfix and location lists as the source of
truth. Notes live in `item.user_data.quickreview`; producer fields remain
unchanged. Persistence is provided by `quickfix_persist` and is optional.

The next architectural step is documented in [`SPINOFF.md`](SPINOFF.md):

1. Extract native list actions and qf UI lifecycle into `quickfix-actions.nvim`.
2. Extract generic formatting and destinations into `quickfix-export.nvim`.
3. Keep `quickfix-persist.nvim` note-agnostic.
4. Keep annotations, resolvers, marks, owned review lists, and note-aware UI in `quickreview.nvim`.

## Repository And Test Layout

Each plugin lives in an independent repository under `~/projects`:

```text
~/projects/quickfix-actions.nvim
~/projects/quickfix-export.nvim
~/projects/quickfix-persist.nvim
~/projects/reviewnotes.nvim
```

There is no monorepo or aggregate installable plugin. Standalone tests add only
the repository under test and its required dependencies to `runtimepath`.
QuickReview integration tests add the sibling Actions, Export, and optional
Persist paths directly. Test setup should accept environment-variable path
overrides and otherwise default to sibling directories, so CI can check out the
repositories anywhere without hard-coded home paths. Use
`QUICKFIX_ACTIONS_PATH`, `QUICKFIX_EXPORT_PATH`, and `QUICKFIX_PERSIST_PATH` for
those overrides.

## Frozen API Boundaries

Plugins integrate through Lua modules, not Ex commands. Commands are thin,
user-facing conveniences which parse command arguments, call the same Lua API,
and report errors. QuickReview therefore calls `require("quickfix_actions")`
and `require("quickfix_export")` directly. User mappings may call either a
command or Lua API.

Actions uses these native list targets:

```lua
{ kind = "quickfix", id = 42 }
{ kind = "location", id = 17, winid = 1001 }
```

For a location list, `winid` is the file window that owns the list, not the
location-list window. Helpers that inspect the current qf window must resolve
its owner before returning a target. An omitted target may mean the current
list for convenience, but once resolved it always includes an ID. Operations
given an explicit ID never fall back to another list: stale IDs, invalid owner
windows, and changed `changedtick` values return `nil, err`. Reads return native
snapshots without rewriting items; replacement and deletion preserve list
title, context, index where possible, and all item metadata.

Export produces ordered, JSON-safe records with this stable generic shape:

```lua
{
  index = 1,
  path = "lua/example.lua",
  line = 10,
  line_end = 12,
  col = 3,
  end_col = 8,
  text = "message",
  type = "E",
  valid = true,
  kind = "quickfix",
}
```

Optional native values remain `nil`; the record does not contain raw native
items or QuickReview IDs. This keeps JSON stable and note-agnostic. Export
continues to preserve native order, resolve valid buffer names, make paths
relative to `root`, skip context rows by default, and report unresolved paths
unless `strict = false`.

The generic text selector is:

```lua
text = function(item, default_text)
  return default_text
end
```

QuickReview adapts its note-aware public selector without exposing notes to
Export:

```lua
generic_opts.text = function(item, default_text)
  local note = annotations.get(item)
  local text = note and note.text or default_text
  return opts.text and opts.text(item, note, text) or text
end
```

Thus `quickfix-export` never requires or inspects QuickReview, while the
existing QuickReview callback remains useful.

Actions and Export are required QuickReview dependencies. QuickReview does
not retain duplicate fallback implementations; setup reports a clear missing
dependency error. Persist remains optional.

Generic commands use `QuickfixActions...` and `QuickfixExport...` names. Note
commands remain under `QuickReview...`. Exact command arguments and mapping
defaults are frozen by characterization tests before moving them; commands are
not an inter-plugin compatibility API. Mapping installation must be
configurable so Actions can coexist with Quicker.

## Current Guarantees

- Native qf/location-list items are canonical.
- Producer `item.text` and arbitrary `user_data` fields are preserved.
- Annotated producer entries are mirrored into the owned `Quickfix Notes` list.
- Unsupported transformed ranges fall back to file-level notes rather than fabricated coordinates.
- Export uses note text for annotated entries and producer text otherwise.
- Generic export supports custom text selection, Markdown prefix/suffix, and multiple destinations.
- Persistence watches only explicitly saved lists and the optional owned review list.
- The native qf renderer is not replaced and `quickfixtextfunc` is not owned.
- Qf UI open/close/toggle helpers are generic Actions features.
- Editable qf `:write` support is deferred until after extraction and is not part of the compatibility contract.

## Extraction Order

1. Add characterization tests that freeze current QuickReview and persistence behavior.
2. Extract qf UI lifecycle, target resolution, list reads, current-entry lookup, replacement, deletion, and clearing into Actions.
3. Extract normalized export records, formatters, and destinations into Export.
4. Add standalone tests for quickfix lists, location lists, stale IDs, ordering, deletion, metadata preservation, UI lifecycle, and export edge cases.
5. Make QuickReview consume the required Actions and Export Lua APIs without changing note behavior.
6. Test on Neovim 0.10 and current stable Neovim, against a recorded Quicker revision, and with both the presence and absence of optional Persist.
7. Remove duplicated generic code after all standalone and cross-repository suites pass.

Editable qf `:write` support is a separate later milestone. It may be explored
only after these APIs and integration suites are stable, and must remain
opt-in, disabled by default, metadata-preserving, stale-list-safe, and disabled
when another plugin owns editable qf buffers.

## Non-Goals

- Do not replace the native qf renderer.
- Do not duplicate Neovim's built-in `[q`, `]q`, `[l`, or `]l` navigation.
- Do not make generic export understand note metadata by default.
- Do not make persistence automatically watch arbitrary producer lists.
- Do not create a second note database.
