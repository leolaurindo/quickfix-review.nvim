# Integrations

QuickfixNotes has two separate extension surfaces:

- `quickfix_persist` stores native quickfix and location-list snapshots and knows nothing about notes.
- `quickfix_actions` owns generic native list access and mutations.
- `quickfix_export` normalizes native lists, formats records, and sends destinations.
- `quickfix_notes` resolves source locations, annotates list items, maintains the owned review list, and supplies note-aware export text.

Do not write a second note database or identify entries by rendered qf text. Native list IDs and `user_data.quickfix_notes.id` are the identities.

## Diff And UI Resolvers

Resolvers live under `lua/quickfix_notes/resolvers/` and are registered by the resolver registry. A resolver provides:

```lua
return {
  name = "my_diff_ui",
  priority = 50,
  renderable = true,
  detect = function(bufnr, winid) end,
  location = function(bufnr, winid)
    return {
      root = "/repo",
      path = "lua/example.lua",
      line = 10,
      line_end = 12,
      side = "new",
      revision = nil,
      hash = nil,
    }
  end,
  range_location = function(bufnr, start_line, end_line) end,
  anchor = function(location, bufnr)
    return location.line_end or location.line
  end,
}
```

`range_location` is required for transformed diff buffers when exact ranges are desired. The registry does not guess a range mapping when the UI row and source row differ; QuickfixNotes falls back to a file-level note instead of saving incorrect coordinates. `anchor` controls the source-buffer triangle location, and should return the bottom line for ranges.

When a resolver can identify the file but cannot map a visual range, QuickfixNotes saves a file-level note instead of dropping the note. The note has no fabricated line number, so AI/export consumers can still inspect the correct file. Resolvers should implement `range_location` whenever they can provide exact source coordinates.

Register a resolver during setup or from another plugin:

```lua
require("quickfix_notes.resolver").register(require("my_resolver"))
```

The existing adapters cover normal buffers, native diffs, Diffview+, CodeDiff, Differ, diffs.nvim, and Neogit. An unknown URI buffer is also supported when its decoded URI contains an existing absolute file path; it receives a file-level note because its rows cannot be mapped safely to source lines. Historical-side navigation falls back to the stored working-tree path when the original diff UI cannot be recreated.

For Diffview+, install `dlyongemallo/diffview-plus.nvim` and use its normal `:Diffview...` commands. QuickfixNotes discovers the active Diffview through `diffview.lib`, records old/new side and revision metadata, and rejects ranges in inline layouts where visible rows do not map directly to source rows.

## Picker Adapters

`quickfix_notes.picker.entries({ source = "owned" })` and
`quickfix_notes.picker.entries({ source = "current" })` return filtered annotated entries. Each entry contains the native list target, note ID, path, range, note text, and file preview coordinates.

The built-in picker uses Snacks when available:

```vim
:QuickfixNotesPick
:QuickfixNotesPickCurrent
```

It re-reads the native list and finds the note ID again before jumping. If Snacks is unavailable, it uses `vim.ui.select`. A Telescope adapter can consume the same `entries()` result without creating an aggregate quickfix list.

## Export Extensions

The export pipeline is:

```text
native list -> normalized records -> formatter -> destination
```

Normalized records contain `index`, `path`, `line`, `line_end`, `col`, `end_col`,
`text`, `type`, `valid`, and list `kind`. Unavailable fields are omitted. They
do not contain raw native items or QuickfixNotes note IDs.

The native `item.text` remains the producer message. QuickfixNotes stores the
full note in `user_data.quickfix_notes.text`; it does not copy or concatenate
the producer message into the note. Native qf rendering cannot display an
arbitrary `user_data` field without taking over the renderer. For export-only
field selection, pass a callback:

```lua
require("quickfix_notes").export({
  text = function(item, note)
    return note and note.text or item.user_data and item.user_data.message or item.text
  end,
})
```

The underlying generic Export selector receives only `(item, default_text)`;
QuickfixNotes supplies the `note` argument in its wrapper.

QuickfixNotes also applies a note's canonical source path and range to its own
records after generic normalization. This preserves diff/source resolver
locations without exposing note metadata to quickfix-export or mutating the
native list.

This callback affects the normalized export record only; it does not mutate the
producer item or its qf display.

Built-in formatters are Markdown and JSON. A formatter module exposes:

```lua
return {
  format = function(records)
    return "payload"
  end,
}
```

Markdown accepts per-export `prefix` and `suffix` strings:

```lua
require("quickfix_notes").export({
  format = "markdown",
  prefix = "# Review\n\n",
  suffix = "\nGenerated by Neovim\n",
})
```

Built-in Export destinations are clipboard, file, and optional Sidekick. A
destination exposes:

```lua
return {
  name = "my_destination",
  send = function(payload, opts)
    return true
  end,
}
```

Register it with:

```lua
local sender = require("quickfix_notes.sender")
sender.register(require("my_destination"))
sender.set_default("my_destination")
```

Other plugins call `require("quickfix_actions")` and
`require("quickfix_export")` directly. `:QuickfixActions...` and
`:QuickfixExport...` are thin user-facing command wrappers.

An explicit `false, err` return is treated as failure, so `ExportAndClear` will not clear after a rejected destination.

## Quickfix Semantics

Normal quickfix and location-list buffers remain native and unmodifiable. QuickfixNotes does not own `quickfixtextfunc`, does not install `BufWriteCmd`, and does not parse rendered qf lines.

Annotating a producer row adds only `user_data.quickfix_notes` to that native item, then mirrors the annotated entry into the owned `Quickfix Notes` list. The producer item text and metadata remain unchanged. The owned copy uses an empty quickfix type so its display is `path|line|note text`.

The qf triangle and floats are configurable:

```lua
require("quickfix_notes").setup({
  quickfix = {
    inline = true,
    float = {
      enabled = true,
      delay = 500,
      command = true,
    },
  },
})
```

`dd` deliberately deletes the current native entry. `QuickfixNotesDelete` removes the annotation while preserving the producer entry.

## Persistence

Use `quickfix_persist` directly for arbitrary named native lists. QuickfixNotes automatically watches only its owned review list. See the sibling plugin README for snapshot namespaces, scope values, restore modes, and watch handles.
