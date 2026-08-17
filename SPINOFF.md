# Quickfix Plugin Spinoff

This document records the proposed split between generic native quickfix tools,
native quickfix persistence, and QuickfixNotes. It is a design boundary and
migration plan, not a requirement to publish three repositories immediately.

## Recommendation

Use three plugins when the generic qf features are intended to be useful on
their own:

1. `quickfix-utils.nvim`: native quickfix/location-list operations.
2. `quickfix-persist.nvim`: named JSON snapshots and watches.
3. `quickfix-notes.nvim`: annotations, review policy, source resolvers, and note UI.

Do not rename `quickfix_persist` to `quickfix_utils`. Persistence is an
independent mechanism with a clear API and should remain independently usable.

The current repository already has the correct persistence boundary. The
utilities should be extracted only after their generic API is tested and named;
the extraction should not be another behavior rewrite.

## Why Split

These features work with every native quickfix or location list, even when no
notes exist:

- Delete the current native entry with `dd`.
- Export the selected native list.
- Normalize native items into ordered export records.
- Format records as Markdown or JSON.
- Send formatter output to clipboard, file, or another destination.
- Pick or jump through generic native list entries.

Those are reasonable standalone qf tools. Keeping them in QuickfixNotes is
convenient but couples users who only want qf tooling to annotation policy.

## What Moves To `quickfix-utils`

Move these mechanisms without changing their behavior:

- The qf/location adapter portions of `lists.lua`: kind detection, target IDs, reads, changedtick checks, item replacement, current-row lookup, and native entry deletion.
- Native path and range extraction that does not know about note metadata.
- The generic portion of `export.lua`: list snapshot to ordered normalized records, including unannotated items.
- Markdown and JSON formatters.
- Destination registration and built-in clipboard/file destinations.
- Generic qf/loclist picker entries and native jump behavior.
- The qf-local `<CR>` and `dd` mappings under utility command names.

The standalone public API should look approximately like:

```lua
local qf = require("quickfix_utils")

qf.setup({})
qf.delete_current()
qf.export({
  list = { kind = "quickfix", id = 42 },
  format = "markdown",
  destination = "clipboard",
})
```

The utility plugin must never require `quickfix_notes`, inspect
`user_data.quickfix_notes`, create an owned list, or apply branch policy.

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

QuickfixNotes should depend on `quickfix-utils` and `quickfix-persist`, then add
annotation-aware behavior around their generic records and targets.

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

QuickfixNotes should receive generic list targets and normalized records from
QuickfixUtils, then provide note-aware callbacks:

```lua
local utils = require("quickfix_utils")

utils.export({
  list = target,
  text = function(item)
    return item.text
  end,
})
```

QuickfixNotes can replace the text selector with:

```lua
text = function(item, note)
  return note and note.text or item.text
end
```

The native list item remains the source of truth. The utility layer must not
copy or rewrite list entries merely to implement export or picker behavior.

## Migration Order

1. Freeze the current native list and annotation tests.
2. Extract generic list target/read/replace/delete operations into a temporary internal module with no behavior change.
3. Extract generic normalized export records and formatter/destination APIs.
4. Add `quickfix-utils.nvim` tests for unannotated qf lists, loclists, stale IDs, ordering, and deletion.
5. Make QuickfixNotes depend on the utility API while retaining compatibility wrappers for one release.
6. Keep `quickfix_persist` as the separate persistence dependency.
7. Move generic commands to `QuickfixUtils...`; retain `QuickfixNotes...` aliases where the command is note-aware.
8. Remove duplicated internal utility code only after both test suites pass.

## Non-Goals

- Do not create an aggregate quickfix list for generic picking.
- Do not make `quickfix-utils` a second persistence plugin.
- Do not use rendered qf buffer text as data.
- Do not put note content in `module`, `pattern`, or producer `text` fields.
- Do not make every existing qf list persistent automatically.

## Current Status

The current implementation is still a two-plugin runtime:

- `quickfix_notes.nvim` contains both note policy and generic qf conveniences.
- `quickfix_persist` is already independent.

The extraction described here is the next architectural refactor, not a
requirement for using the current plugin.
