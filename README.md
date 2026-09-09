# quickfix-review.nvim

Add review notes to almost any location, such as source code,
quickfix/location-list entries, Git diff rows and more. Notes remain attached to
their original producer items, while a
dedicated `Quickfix Review` quickfix list provides a central view for reviewing,
persisting, and exporting them.

Quickfix Review works standalone or as part of the [quickfix-kit.nvim](https://github.com/leolaurindo/quickfix-kit.nvim) package.

Requires Neovim 0.10+.

Dependencies:

- Required:
    - [quickfix-actions.nvim](https://github.com/leolaurindo/quickfix-actions.nvim),
    - [quickfix-export.nvim](https://github.com/leolaurindo/quickfix-export.nvim)
- Optional:
    - [quickfix-persist.nvim](https://github.com/leolaurindo/quickfix-persist.nvim)
    - [quickfix-diffs.nvim](https://github.com/leolaurindo/quickfix-diffs.nvim) supplies diff metadata for note locations.

## Installation

With lazy.nvim:

```lua
{
  "leolaurindo/quickfix-review.nvim",
  dependencies = {
    "leolaurindo/quickfix-actions.nvim",
    "leolaurindo/quickfix-export.nvim",
  },
  opts = {},
}
```

Add `quickfix-persist.nvim` for automatic note-list persistence and
`quickfix-diffs.nvim` for diff metadata integration.

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({
  "https://github.com/leolaurindo/quickfix-actions.nvim",
  "https://github.com/leolaurindo/quickfix-export.nvim",
  "https://github.com/leolaurindo/quickfix-review.nvim",
}, { load = true })
require("quickfix_review").setup()
```

## Setup

```lua
require("quickfix_review").setup({
  send = "clipboard",
})
```

Review uses Lua APIs to integrate with sibling plugins. Commands are user-facing
wrappers. A note is stored on its native producer item in
`item.user_data.quickfix_review` and mirrored into the branch-scoped
`Quickfix Review` quickfix list. Producer text and metadata stay unchanged.

## Agent workflow

Quickfix Review can receive findings from coding agents through the repository's
[`skills/quickfix-review/SKILL.md`](skills/quickfix-review/SKILL.md) workflow:

1. The agent reviews the changeset and writes versioned `findings.json`.
2. Import the findings with `:QuickfixReviewImport findings.json`.
3. Review and edit the imported notes in the owned Quickfix Review list.
4. Export the selected notes to the clipboard or a file, or send them to
   Sidekick when `sidekick.nvim` is installed. Use
   `:QuickfixReviewExportAgent` to send only agent-authored notes.

The skill is also usable without live integration: the agent writes the file and
asks you to run the import command. See [Import](#import) for the JSON format.

Sidekick is an optional destination supplied by `quickfix-export.nvim`:

```lua
require("quickfix_review").setup({
  send = "sidekick",
})
```

Without this configuration, exports use the default clipboard destination.
See [Export](#export) for custom formats and destinations.

## Quick start

1. Open a native quickfix or location list with `:copen` or `:lopen`.
2. In a source buffer, run `:QuickfixReviewAdd` at the cursor, or select a range
   first to annotate that range.
3. Alternatively, if a quickfix or location-list entry already exists, place
   the cursor on a row and press `a` or `i` to add or edit its note.
4. Save the note with `<C-s>` or `q`.
5. Open all notes with `:QuickfixReviewList`, then export with
   `:QuickfixReviewExport`.

## Commands

| Command | Action |
| --- | --- |
| `:QuickfixReviewAdd` | Add a note at the cursor, visual range, or qf row |
| `:QuickfixReviewAddFile` | Add a file-level note |
| `:[range]QuickfixReviewReanchor[!]` | Move a note; `!` makes it file-level |
| `:QuickfixReviewEdit` | Edit a note |
| `:QuickfixReviewDelete` | Remove a note |
| `:QuickfixReviewList` | Open the owned notes quickfix list |
| `:QuickfixReviewPick` | Pick an owned note |
| `:QuickfixReviewPickCurrent` | Pick a note in the current list |
| `:QuickfixReviewSearch` | Search the current list by path, entry text, or note text |
| `:QuickfixReviewExport` | Export the selected list |
| `:QuickfixReviewExportUser` | Export user-authored notes only |
| `:QuickfixReviewExportAgent` | Export agent-authored notes only |
| `:QuickfixReviewExportList` | Export the current native list |
| `:QuickfixReviewExportAndClear` | Export, then clear on success |
| `:QuickfixReviewClear` | Clear annotations or owned entries |
| `:QuickfixReviewSaveList <name>` | Save the selected native list |
| `:QuickfixReviewLoadList <name>` | Load a named native list |
| `:QuickfixReviewImport <file>` | Import findings from JSON |
| `:QuickfixReviewHide` / `:QuickfixReviewShow` | Toggle source marks |
| `:QuickfixReviewHover` | Show the qf row's note |
| `:QuickfixReviewQuit` | Save and close the note editor (buffer-local) |
| `:QuickfixReviewNext` / `:QuickfixReviewPrev` | Pick the next/previous note |
| `:QuickfixReviewSend` | Export through the configured destination |

`QuickfixReviewAdd` accepts a range. `QuickfixReviewReanchor` accepts a range
and `!` for file scope. Notes can be added from a source buffer, a quickfix row,
a location-list row, or a diff row.

### Quickfix mappings

Quickfix and location-list buffers remain native and unmodifiable:

- `<CR>` jumps to the native entry.
- `dd` deletes the native entry.
- `a` and `i` add or edit its note.

Global mappings are disabled by default to avoid collisions. Add only the ones
you want under `keys`, for example:

```lua
require("quickfix_review").setup({
  keys = {
    note = "<leader>rn",
    next = "]r",
    prev = "[r",
  },
})
```

`QuickfixReviewSearch` searches every entry in the current native quickfix or
location list by file path, producer text, and attached note text. With Snacks it
uses a compact live-search select picker. Confirming a result returns focus to
the list and places the cursor on that row without opening its source buffer.
`QuickfixReviewPick` and `QuickfixReviewPickCurrent` remain note-oriented source
navigation pickers.

## Configuration

Defaults:

| Option | Default | Purpose |
| --- | --- | --- |
| `send` | `"clipboard"` | Destination for `QuickfixReviewSend` |
| `send_opts` | `{}` | Destination options |
| `warn_stale` | `true` | Warn when a note's source changed |
| `actions` | `{ mappings = { qf = false } }` | Actions setup forwarded by Review |
| `export` | `{}` | Export setup forwarded by Review |
| `quickfix_title` | `"Quickfix Review"` | Owned notes-list title |
| `persist_review_list` | `true` | Watch the owned notes list when Persist is available |
| `scope_policy` | `"branch"` | `branch`, `repository`, or `custom` note scope |
| `inline` | `true` | Show source note marks |
| `glyph` | `"▲"` | Source mark glyph |
| `float` | `{ enabled = true, delay = 500, permanent = false }` | Source note hover |
| `quickfix.prefill` | `true` | Start new qf notes with producer text |
| `quickfix.inline` | `true` | Show marks in qf buffers |
| `quickfix.float` | `{ enabled = true, delay = 500, permanent = false, command = true }` | qf note hover |
| `keys` | `{}` | Optional global note, export, list, and navigation mappings |

Global mappings are disabled by default. Configure only the mappings you want;
see the Quickfix mappings section above.

Example:

```lua
require("quickfix_review").setup({
  quickfix = {
    prefill = false,
    inline = true,
    float = { enabled = true, delay = 500, command = true },
  },
  warn_stale = false,
})
```

New notes use producer text when `quickfix.prefill = true`; existing notes use
their saved text. Producer fields and text remain unchanged. The owned
`Quickfix Review` list displays note text only.

## Notes and locations

A source-buffer note, quickfix note, location-list note, and diff note use the
same annotation model. The producer item keeps its native fields; the owned
`Quickfix Review` quickfix list stores the note text and location for review,
picking, persistence, and export.

Annotations are stored in `item.user_data.quickfix_review`:

```lua
{
  version = 1,
  id = "stable-id",
  text = "Full multiline note",
  created_at = 1786920000,
  updated_at = 1786920000,
  location = {
    root = "/repo", path = "lua/example.lua", line = 10, line_end = 12,
    side = "new", revision = nil, hash = nil, resolver = "normal",
  },
}
```

`:QuickfixReviewAddFile` creates a note without line numbers. Re-anchoring
preserves the note ID, text, creation time, metadata, and producer origin;
missing producer entries are not recreated.

Locations use snapshot coordinates. Worktree notes capture whole-file
fingerprints; Diffs notes use Git fingerprints. Changed sources produce advisory
stale warnings and `stale = true` export records. Suppress warnings and Markdown
stale labels with:

```lua
require("quickfix_review").setup({ warn_stale = false })
require("quickfix_review").export({ warn_stale = false })
```

## Import

Import versioned agent findings into the owned notes quickfix list:

```lua
require("quickfix_review").import_findings("findings.json", { source = "agent" })
```

Each finding requires `text` and a repository-relative `path`; `line` and
`line_end` are optional. Stable string IDs update existing findings; findings
without IDs match by location. `severity`, `confidence`, `category`, `evidence`,
and `suggestion` are retained in `note.metadata`. Imported agent findings use
`metadata.origin = "agent"`; existing notes without an origin are treated as
user-authored.

```json
{
  "version": 1,
  "source": "agent",
  "origin": "agent",
  "findings": [
    {
      "id": "agent-001",
      "path": "lua/example.lua",
      "line": 10,
      "line_end": 12,
      "text": "The failure path skips cleanup.",
      "severity": "high",
      "confidence": 0.94,
      "evidence": "The error return bypasses cleanup.",
      "suggestion": "Run cleanup before returning the error."
    }
  ]
}
```

## Export

Exports preserve native order. Annotated items use note text; unannotated items
use producer text. The producer list retains its original text.

```lua
require("quickfix_review").export({
  list = { kind = "quickfix", id = 42 },
  format = "markdown",
  destination = "clipboard",
  prefix = "# Review\n\n",
})
```

`format` accepts `markdown`, `json`, or `function(records, opts)`. A custom
formatter returns a string or `nil, err`; errors prevent sending and clearing.
`text(item, note, default_text)` can combine producer and note text:

```lua
require("quickfix_review").export({
  text = function(item, note)
    return note and note.text or item.user_data and item.user_data.message or item.text
  end,
})
```

Structured records include annotation `metadata`; IDs and timestamps are not
exported. Markdown stays concise and JSON/custom formatters receive metadata.
Agent-authored Markdown records include a `[source: agent]` label. Use
`:QuickfixReviewExportUser` or `:QuickfixReviewExportAgent` to filter by note
origin. Built-in destinations are `clipboard`, `file`, and optional `sidekick`.
See [`docs/integrations.md`](docs/integrations.md) for extension contracts.

## Integrations

Review remains standalone and uses sibling plugin APIs directly; it never depends
on `quickfix-kit.nvim` itself. The package boundary is:

| Module | Role in Review | Status |
| --- | --- | --- |
| [quickfix-actions.nvim](https://github.com/leolaurindo/quickfix-actions.nvim) | Read, mutate, and identify native quickfix/location lists | Required |
| [quickfix-export.nvim](https://github.com/leolaurindo/quickfix-export.nvim) | Normalize records, format output, and send it | Required |
| [quickfix-persist.nvim](https://github.com/leolaurindo/quickfix-persist.nvim) | Persist the owned notes list and explicitly selected lists | Optional |
| [quickfix-diffs.nvim](https://github.com/leolaurindo/quickfix-diffs.nvim) | Supply Git ranges, revisions, and fingerprints for diff notes | Optional integration |

Review stores notes on native producer items and mirrors them into its owned
notes quickfix list. Kit only initializes these modules together. Review does
not parse rendered qf text or require external UI plugins.

Built-in source resolvers cover normal buffers, native diffs, Diffview+, CodeDiff,
Differ, diffs.nvim, and Neogit when those UIs are installed. An unknown
file-backed URI becomes a file-level note instead of receiving guessed lines.
See [`docs/integrations.md`](docs/integrations.md) for resolver, picker, and
custom formatter/destination contracts.

## Git diffs and persistence

With optional [quickfix-diffs.nvim](https://github.com/leolaurindo/quickfix-diffs.nvim), Review recognizes version 1
`item.user_data.quickfix_diffs`: new-side hunks use new ranges, deletion-only
hunks use old ranges, and full-file rows become file-level notes. Each Diffs run
creates a new native list; Review never guesses hunk reattachment. Native
navigation still opens worktree files.

Persist is optional. When available, Review automatically watches only its owned
notes quickfix list as `quickfix_review/review` under repository/branch scope. Use
`quickfix_persist` directly for arbitrary quickfix and location lists.

## Local development and tests

```sh
nvim -u test/manual_init.lua
nvim --headless -u NONE -l test/run.lua
nvim --headless -u NONE -l test/run_export_ui.lua
nvim --headless -u NONE -l test/run_notes.lua
nvim --headless -u NONE -l test/run_with_persist.lua
nvim --headless -u NONE -l test/run_with_diffs.lua
luacheck lua test
```

Sibling paths can be overridden with `QUICKFIX_ACTIONS_PATH`,
`QUICKFIX_EXPORT_PATH`, `QUICKFIX_PERSIST_PATH`, and `QUICKFIX_DIFFS_PATH`.
