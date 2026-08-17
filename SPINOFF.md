# Quickfix Plugin Spinoff

This document records the proposed split between generic native quickfix
actions, export, persistence, and QuickfixNotes. It is a design boundary and
migration plan, not a requirement to publish four repositories immediately.

## Recommendation

Use four plugins with one-way dependencies:

1. `quickfix-actions.nvim`: native quickfix/location-list actions and qf UI lifecycle.
2. `quickfix-export.nvim`: normalized records, formatters, and destinations.
3. `quickfix-persist.nvim`: named JSON snapshots and watches.
4. `quickfix-notes.nvim`: annotations, review policy, source resolvers, and note UI.

`quickfix-export` and `quickfix-persist` use `quickfix-actions` for native list
access. `quickfix-notes` uses all three, with persistence remaining optional.
None of the generic plugins require `quickfix-notes`.

The current repository already has the correct persistence boundary. The
actions and export layers should be extracted only after their generic APIs are
tested and named; the extraction should not be another behavior rewrite.

## Repository Strategy

Use four independent repositories under `~/projects`: `quickfix-actions.nvim`,
`quickfix-export.nvim`, `quickfix-persist.nvim`, and `quickfix-notes.nvim`.
There is no monorepo or aggregate installable plugin.

Standalone tests add the repository under test and its required dependencies
to `runtimepath`. Cross-plugin tests use the sibling local repository paths,
with `QUICKFIX_ACTIONS_PATH`, `QUICKFIX_EXPORT_PATH`, and
`QUICKFIX_PERSIST_PATH` overrides for CI checkouts. Each repository owns its Lua
namespace, README, tests, dependency declaration, and release lifecycle.

## Quicker Coexistence

All four plugins should be installable alongside `quicker.nvim`:

- `quicker.nvim` owns quickfix presentation, styling, context expansion, and its editable qf buffer.
- `quickfix-actions.nvim` owns generic list actions and may use native `copen`, `cclose`, and `cwindow` behavior for lifecycle operations.
- `quickfix-actions.nvim` never owns `quickfixtextfunc`.
- Editable qf `:write` behavior is deferred until after extraction. If later implemented, only one plugin may own it and the Actions experiment must stay disabled when Quicker owns editing.
- `quickfix-export.nvim` and `quickfix-persist.nvim` operate on native list data and do not care which renderer is visible.
- `quickfix-notes.nvim` keeps note metadata in native `user_data` and should not make qf buffers modifiable.

Mapping ownership should be configurable so users can choose whether Actions or
Quicker owns qf-window convenience mappings. Integration tests must verify that
Quicker expand, collapse, refresh, and edit operations preserve native item
metadata, including `user_data.quickfix_notes`.

## Why Split

These features work with every native quickfix or location list, even when no
notes exist:

- Delete the current native entry with `dd`.
- Export the selected native list.
- Pick or jump through generic native list entries.
- Delete, clear, or safely replace native list entries.

Those are reasonable standalone qf features. Keeping them in QuickfixNotes is
convenient but couples users who only want qf tooling to annotation policy.

## What Moves To `quickfix-actions`

Move these mechanisms without changing their behavior:

- The generic portions of `lists.lua`: kind detection, target IDs, reads, changedtick checks, item replacement, current-row lookup, clearing, and deletion.
- Generic qf/loclist picker entries and native jump behavior.
- Open, close, and toggle quickfix/location-list windows, including height and focus options.
- The qf-local `<CR>` and `dd` mappings. `[q`, `]q`, `[l`, and `]l` remain Neovim defaults.
- Programmatic `current`, `item`, `replace`, `clear`, and `delete` operations.

The standalone public API should look approximately like:

```lua
local actions = require("quickfix_actions")

actions.setup({})
actions.delete_current()
actions.pick()
```

The actions plugin must never require `quickfix_notes`, inspect
`user_data.quickfix_notes`, create an owned list, or apply branch policy.

### Deferred Experimental `:write` Support

Do not implement editable qf/location-list buffers during extraction. After the
standalone APIs and cross-plugin integration tests stabilize, Actions may
separately experiment with applying a successful `:write` back to the native
list. This remains opt-in, disabled by default, and outside the compatibility
contract.

The experiment must validate parsed rows, preserve item metadata, reject
ambiguous or malformed edits, and check `changedtick` before replacing the
list. It must not take ownership of `quickfixtextfunc` or make the native list
buffer editable by default. If these constraints cannot be met reliably, the
feature should remain absent rather than imitate an editable qf UI poorly.

## What Moves To `quickfix-export`

Keep export useful for every native list:

- Read a target through `quickfix-actions`.
- Normalize entries into ordered records.
- Markdown and JSON formatters.
- Prefix and suffix options.
- Custom text selectors.
- Clipboard, file, and other destinations.

The default text is `item.text`. QuickfixNotes supplies a note-aware selector
when it wants annotated export behavior.

## What Stays In `quickfix-notes`

Keep these note-specific policies and behaviors:

- `annotations.lua` and the `user_data.quickfix_notes` schema.
- Note IDs, note text, and timestamps.
- The owned `Quickfix Notes` list and its ownership/scope context.
- Mirroring producer annotations into the owned review list.
- Source-buffer triangles and note hover floats.
- Normal/diff/source resolver registry and adapters.
- Note filtering in `QuickfixNotesPick` and `QuickfixNotesPickCurrent`.
- Note-aware export text selection and `ExportAndClear` policy.
- The plain-text note editor and note commands.

QuickfixNotes should depend on `quickfix-actions` and `quickfix-export`, then
optionally use `quickfix-persist` for the owned review list. It must report a
clear error when a required plugin is missing rather than retaining duplicate
fallback implementations.

## What Stays In `quickfix-persist`

Keep persistence completely note-agnostic:

- Capture and restore native qf/location snapshots.
- Namespaces, snapshot names, scopes, and safe paths.
- Watch handles, debounce, flush, unwatch, and shutdown.
- Atomic writes and schema validation.
- Explicit restore modes.
- Optional `QuickfixSave` and `QuickfixLoad` commands.

`quickfix_persist` must not know what a note is or automatically watch arbitrary
producer lists.

## Integration Contract

QuickfixNotes should receive generic list targets from QuickfixActions and
normalized records from QuickfixExport, then provide note-aware callbacks:

```lua
local actions = require("quickfix_actions")
local export = require("quickfix_export")

local target = { kind = "quickfix", id = 42 }
local entry = actions.item(target, 1)
export.run({ list = target })
```

Plugins call these Lua modules directly. `QuickfixActions...` and
`QuickfixExport...` commands are thin user interfaces, not the inter-plugin
API.

Actions targets are stable native identities:

```lua
{ kind = "quickfix", id = 42 }
{ kind = "location", id = 17, winid = 1001 }
```

The location-list `winid` is its owning file window. An explicit stale ID or
invalid owner window is an error and must never fall back to the current list.
Mutations use `changedtick` checks and preserve native item metadata.

Export records are ordered and JSON-safe. They contain `index`, `path`, `line`,
`line_end`, `col`, `end_col`, `text`, `type`, `valid`, and list `kind`, with
unavailable values omitted. They do not contain raw native items or note IDs.
The generic selector receives only the native snapshot item and default text:

```lua
text = function(item, default_text)
  return default_text
end
```

QuickfixNotes supplies a wrapper which reads annotations itself and preserves
its note-aware callback:

```lua
generic_opts.text = function(item, default_text)
  local note = annotations.get(item)
  local text = note and note.text or default_text
  return opts.text and opts.text(item, note, text) or text
end
```

The native list item remains the source of truth. The actions and export layers
must not copy or rewrite list entries merely to implement picker or export
behavior.

## Migration Order

1. Add characterization tests that freeze current native list, annotation, command, and mapping behavior.
2. Extract generic list target/read/replace/delete operations into `quickfix-actions` with no behavior change.
3. Extract normalized export records and formatter/destination APIs into `quickfix-export`.
4. Add standalone tests for unannotated qf lists, loclists, stale IDs, ordering, deletion, metadata preservation, UI lifecycle, and export edge cases.
5. Make QuickfixNotes depend on the actions and export APIs.
6. Keep `quickfix-persist` note-agnostic and use it for the owned review list only when available.
7. Move generic commands to `QuickfixActions...` and `QuickfixExport...`; keep note commands under `QuickfixNotes...`.
8. Test Quicker coexistence at a recorded revision, Neovim 0.10 and current stable Neovim, and QuickfixNotes with and without optional Persist.
9. Remove duplicated internal code only after all standalone and cross-repository suites pass.

## Non-Goals

- Do not create an aggregate quickfix list for generic picking.
- Do not make `quickfix-actions` a second persistence plugin.
- Do not make `quickfix-export` understand note metadata by default.
- Do not replace the native qf renderer or take ownership of `quickfixtextfunc`.
- Do not make experimental qf `:write` support part of the default setup.
- Do not use rendered qf buffer text as data.
- Do not put note content in `module`, `pattern`, or producer `text` fields.
- Do not make every existing qf list persistent automatically.

## Current Status

The current implementation is still a two-plugin runtime:

- `quickfix-notes.nvim` contains note policy, generic actions, and export conveniences.
- `quickfix_persist` is already independent.

The four-plugin extraction described here is the next architectural refactor,
not a requirement for using the current plugin.
