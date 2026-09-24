# quickfix-review.nvim

Add review notes to almost any location, such as source code,
quickfix/location-list entries, Git diff rows and more. Notes stay visible in source 
buffers and native lists—while remaining attached to their original producer items. 
A dedicated `Quickfix Review` quickfix list also provides a central view for 
reviewing, persisting, and exporting them.

Quickfix Review supports a bi-directional coding-agent workflow: send your
location-aware notes to an agent, then receive its findings back as notes at the
relevant files and ranges. Human and agent feedback share the same visible review
surface instead of being confined to a chat transcript or separate report.

Quickfix Review works standalone or as part of the [quickfix-kit.nvim](https://github.com/leolaurindo/quickfix-kit.nvim) package.

## Demos

**Bi-directional agent integration**

![Two source-buffer notes are sent to an agent and two findings return to the Quickfix Review list](assets/agent-workflow.gif)

Any coding agent can return location-aware notes by writing one complete
version 2 payload to `.quickfix-review/agent-response.json`, then creating the
matching `.ready` marker. Quickfix Review watches that mailbox and imports the
completed response automatically. The shipped
[quickfix-review skill](skills/quickfix-review/SKILL.md) defines the payload
format and mailbox lifecycle.


**Integrations**

Quickfix Review integrates with native diffs, Diffview+, CodeDiff,
[Differ](https://github.com/leolaurindo/differ.nvim), `diffs.nvim`, and Neogit
when they are installed. Differ is one example: its mapped changed lines retain
location-aware notes and markers.

[![Quickfix Review markers and notes render in a Differ view](assets/differ.gif)](https://github.com/leolaurindo/differ.nvim)

You can also add notes to any source buffer with `:QuickfixReviewAdd`, or from
native quickfix and location lists. Custom UIs can supply their own buffer
integration; see the [integration guide](docs/integrations.md).


### Other examples
<details>
<summary>You can write directly on any quickfix list</summary>

![Notes added to native grep quickfix entries are exported as Markdown](assets/quickfix-list.gif)

</details>



<details>
<summary>With quickfix-diffs </summary>

See [quickfix-diffs](https://github.com/leolaurindo/quickfix-diffs.nvim)

![A Quickfix Diffs hunk receives a Quickfix Review note](assets/git-diffs.gif)

</details>

## Installation

Requires Neovim 0.10+.

Dependencies:

- Required:
    - [quickfix-actions.nvim](https://github.com/leolaurindo/quickfix-actions.nvim),
    - [quickfix-export.nvim](https://github.com/leolaurindo/quickfix-export.nvim)
- Optional:
    - [quickfix-persist.nvim](https://github.com/leolaurindo/quickfix-persist.nvim)
    - [quickfix-diffs.nvim](https://github.com/leolaurindo/quickfix-diffs.nvim) supplies diff metadata for note locations.

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
  nerd_font = true, -- Set false when Nerd Font glyphs are unavailable.
})
```

Review uses Lua APIs to integrate with sibling plugins. Commands are user-facing
wrappers. Neovim cannot detect the font selected by a terminal, so Nerd Font
icons are enabled by default; set `nerd_font = false` to use `✎` and `AGENT`
portable fallbacks. Explicit `glyph` and `quickfix.agent_label.text` values still
override either mode. A note is stored on its native producer item in
`item.user_data.quickfix_review` and mirrored into the branch-scoped
`Quickfix Review` quickfix list. Producer text and metadata stay unchanged.

## Agent workflow

Quickfix Review makes agent communication bi-directional. You can send selected,
location-aware notes to a coding agent, and the agent can return structured
findings through the repository's
[`skills/quickfix-review/SKILL.md`](skills/quickfix-review/SKILL.md) workflow.
Returned findings become regular Quickfix Review notes: they are visible at their
source locations, identifiable as agent-authored in native lists, and collected
in the owned Quickfix Review list alongside your notes.

For an optional response round trip, explicitly ask Sidekick to use the
[Quickfix Review skill](skills/quickfix-review/SKILL.md):

1. Add notes from source buffers, quickfix/location-list entries, or diff rows.
2. Send selected user-authored notes to Sidekick with
   `:QuickfixReviewSendAgent`, optionally submitting immediately with `!`.
3. The skill asks the agent to return versioned notes JSON to the repository
   response mailbox.
4. Quickfix Review watches that mailbox and imports completed responses
   automatically. You can also import a response explicitly with
   `:QuickfixReviewImport [file]`.
5. Review or edit the returned notes where they apply or in the central list.

See [Import](#import) for the JSON format and mailbox lifecycle.

Plugin managers install the skill with the plugin but do not register it with
coding-agent clients. Install it using the mechanism supported by your client.
For clients that discover `~/.agents/skills`, symlink the shipped directory:

```sh
mkdir -p ~/.agents/skills
ln -s /path/to/quickfix-review.nvim/skills/quickfix-review ~/.agents/skills/quickfix-review
```

A repository-local `.agents/skills/quickfix-review/SKILL.md` may be used instead
when the client supports project skills. A symlink keeps the skill updated with
the plugin; copying it requires manual updates.

Sidekick is an optional destination supplied by `quickfix-export.nvim`:

```lua
require("quickfix_review").setup({
  send = "sidekick",
})
```

Without this configuration, exports use the default clipboard destination.
See [Export](#export) for custom formats and destinations.

Run `:QuickfixReviewSendAgent` to insert the selected user-authored notes into
Sidekick, or `:QuickfixReviewSendAgent!` to submit immediately. Ordinary sends
contain the formatted notes without a required prompt, findings JSON, or mailbox
write. Use `:QuickfixReviewSendAgentAndClear[!]` to clear all selected notes only
after a successful send. Response generation/import is optional; explicitly
request the [Quickfix Review skill](skills/quickfix-review/SKILL.md) when you want
findings returned as importable notes. The response watcher can be disabled with
`agent.response.watch = false`; its mailbox lifecycle is documented in
[Import](#import).

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
| `:QuickfixReviewListFile` | Open notes for the current source file |
| `:QuickfixReviewPick` | Pick an owned note |
| `:QuickfixReviewPickCurrent` | Pick a note in the current list |
| `:QuickfixReviewSearch` | Search the current list by path, entry text, or note text |
| `:QuickfixReviewExport[!]` | Export using the configured template; `!` includes agent notes |
| `:QuickfixReviewExportFromTemplate[!]` | Choose a one-shot template and export; `!` includes agent notes |
| `:QuickfixReviewSendAgent[!]` | Send user notes to Sidekick using the configured template; `!` submits immediately |
| `:QuickfixReviewSendAgentFromTemplate[!]` | Choose a one-shot template and send to Sidekick; `!` submits immediately |
| `:QuickfixReviewSendAgentAndClear[!]` | Send user notes, then clear all notes on success |
| `:QuickfixReviewReloadAgentResponse` | Retry retained agent responses |
| `:QuickfixReviewExportUser` | Export user-authored notes only |
| `:QuickfixReviewExportAgentNotes` | Export agent-authored notes only |
| `:QuickfixReviewExportList` | Export the current native list |
| `:QuickfixReviewExportAndClear[!]` | Export and clear matching notes; `!` includes agent notes |
| `:QuickfixReviewClear` | Clear annotations or owned entries |
| `:QuickfixReviewClearAgent` | Clear agent-authored notes in the current review scope |
| `:QuickfixReviewSaveList <name>` | Save the selected native list |
| `:QuickfixReviewLoadList <name>` | Load a named native list |
| `:QuickfixReviewImport [file]` | Import findings from JSON; defaults to the repository mailbox path |
| `:QuickfixReviewHide` / `:QuickfixReviewShow` | Toggle source marks |
| `:QuickfixReviewHover` | Show a qf-row note or a source note containing the cursor |
| `:QuickfixReviewHoverAll` | Toggle persistent note overlays at visible source-range endpoints |
| `:QuickfixReviewHoverToggle` | Toggle the automatic source/qf note hover |
| `:QuickfixReviewQuit` | Save and close the note editor (buffer-local) |
| `:QuickfixReviewNext` / `:QuickfixReviewPrev` | Pick the next/previous note |
| `:QuickfixReviewSend[!]` | Send without agent notes; `!` includes them |

`:QuickfixReviewList` keeps the native read-only quickfix list and uses native
wrapping for the path and note text in either layout. Set `notes_list.vertical`
to `true` for a vertical split and customize its width and wrap options. Run
`:QuickfixReviewListFile` from a source buffer to open a filtered native view of
that file's notes without changing the canonical owned notes list.

`QuickfixReviewAdd` accepts a range. `QuickfixReviewReanchor` accepts a range
and `!` for file scope. Notes can be added from a source buffer, a quickfix row,
a location-list row, or a diff row. Range indicators and automatic source hover
appear at both endpoints; hover does not open while moving through every interior
line. Run `:QuickfixReviewHover` explicitly to show notes whose range contains
the cursor. In a source window, `:QuickfixReviewHoverAll` toggles persistent
per-note overlays at visible endpoints; scrolling hides off-screen notes and
reveals newly visible ones, while leaving the window disables the overlays.

### Export, send, and clear semantics

Regular export and send commands use the configured `template` without opening a
picker. The built-ins are `plain`, `check these notes`, `broader review`,
`question`, and `implement`; `plain` adds no prompt text. The `...FromTemplate`
commands open a one-shot selector and do not change the configured default.
Custom entries in `templates` accept a prompt string or `{ prefix, suffix }`,
using quickfix-export's framing API:

```lua
require("quickfix_review").setup({
  template = "review carefully",
  templates = {
    ["review carefully"] = {
      prefix = "Review each note carefully against the code.\n\n",
    },
  },
})
```

From a quickfix/location-list window these commands target the current list;
elsewhere they target the owned Quickfix Review list for the active scope.

- General export and send commands retain ordinary unannotated producer rows but
  omit agent-authored notes by default. Their `!` variants include agent notes.
- `ExportUser` and `ExportAgent` include only annotated notes of that origin.
- `SendAgent[!]` always sends only user-authored notes to Sidekick; `!` means
  submit immediately rather than include agents.
- `ExportAndClear` clears user notes only after a successful export, preserving
  agent notes. Its `!` variant exports and clears both origins.
- `SendAgentAndClear[!]` sends only user notes, then clears all notes in the
  selected target after success. Its `!` also means submit immediately.
- Failed exports/sends never clear notes. Clearing annotations never deletes
  native producer rows.
- Clearing a producer list removes annotations and their owned mirrors. Clearing
  the owned list removes owned entries but does not rewrite another native
  producer list that still carries an annotation.

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
| `template` | `"plain"` | Default export/send template |
| `templates` | `{}` | Custom template framings keyed by name |
| `quickfix_title` | `"Quickfix Review"` | Owned notes-list title |
| `notes_list` | `{ vertical = false, width = 40, wrap = true, linebreak = true, breakindent = true }` | Notes-list window layout and wrapping |
| `persist_review_list` | `true` | Watch the owned notes list when Persist is available |
| `scope_policy` | `"branch"` | `branch`, `repository`, or `custom` note scope |
| `nerd_font` | `true` | Use Nerd Font pencil and robot glyphs; set `false` for portable fallbacks |
| `inline` | `true` | Show source note marks |
| `glyph` | Nerd Font pencil or `✎` | Override the source note glyph |
| `float` | `{ enabled = true, delay = 500, permanent = false }` | Source note hover: `delay` is the idle time in ms before it appears, `permanent = true` forces `delay = 0`. The hover is placed at the end of the text on the cursor's line. `:QuickfixReviewHoverToggle` switches the automatic hover at runtime |
| `quickfix.prefill` | `true` | Start new qf notes with producer text |
| `quickfix.inline` | `true` | Show marks in qf buffers |
| `quickfix.agent_label` | `{ enabled = true }` | Nerd Font robot or `AGENT` fallback; `text` overrides it |
| `quickfix.float` | `{ enabled = true, delay = 500, permanent = false, command = true }` | qf note hover |
| `agent.protect_git` | `true` | Best-effort repository-local Git exclusion |
| `agent.response.watch` | `true` | Watch and automatically import responses; set to `false` to opt out |
| `agent.response.path` | `".quickfix-review/agent-response.json"` | Consumed agent response mailbox |
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

Import versioned agent notes into the owned notes quickfix list:

```vim
:QuickfixReviewImport
:QuickfixReviewImport path/to/findings.json
```

The argument is optional and defaults to the configured repository response path,
`.quickfix-review/agent-response.json`. The equivalent Lua API accepts the same
optional source. New payloads use `version: 2` with a top-level `notes` array;
legacy `version: 1` payloads with `findings` remain accepted.

Each note requires `text` and a repository-relative `path`; `line` and
`line_end` are optional. Stable string IDs update existing notes; notes without
IDs match by location. `severity`, `confidence`, `category`, `evidence`, and
`suggestion` are retained in `note.metadata`. Imported agent notes use
`metadata.origin = "agent"`; existing notes without an origin are treated as
user-authored. Agent notes use the robot glyph in source and quickfix/location-list
buffers; user notes use the pencil in both. Without Nerd Fonts they fall back to
`AGENT` and `✎`. Indicators share the same theme-aware color and never change
native item text.

```json
{
  "version": 2,
  "origin": "agent",
  "notes": [
    {
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
General exports omit agent-authored notes by default; pass
`include_agent_notes = true` or use `:QuickfixReviewExport!` to include them.
`:QuickfixReviewExportUser` and `:QuickfixReviewExportAgentNotes` select one origin.
Built-in destinations are `clipboard`, `file`, and optional `sidekick`.
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
