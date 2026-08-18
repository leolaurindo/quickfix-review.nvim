# quickreview.nvim

A code review workflow around quickfix lists. Take notes on any buffer (including diffs) and export to AI. Persistent, branch-scoped and composable.

Annotate Neovim quickfix and location-list entries, keep a consolidated
branch-scoped review list, and export any native list.
Requires Neovim 0.10 or newer, plus
[quickfix-actions.nvim](https://github.com/leolaurindo/quickfix-actions.nvim)
and [quickfix-export.nvim](https://github.com/leolaurindo/quickfix-export.nvim).
[quickfix-persist.nvim](https://github.com/leolaurindo/quickfix-persist.nvim)
is optional.

```lua
require("quickreview").setup({
  send = "clipboard",
})
```

Plugins call the sibling APIs directly through Lua modules. Commands are
user-facing wrappers, not inter-plugin APIs.

## Commands

- `:QuickReviewAdd` adds a note at the source cursor, visual range, or current qf row.
- `:QuickReviewEdit` and `:QuickReviewDelete` edit or remove an annotation.
- `:QuickReviewList` opens the owned review list.
- `:QuickReviewPick` picks owned annotations; `:QuickReviewPickCurrent` picks annotations in the current native list.
- `:QuickReviewExport` exports the displayed native list from a qf buffer, otherwise the owned review list.
- `:QuickReviewExportAndClear` clears only after a successful destination result.
- `:QuickReviewSaveList <name>` and `:QuickReviewLoadList <name>` persist explicitly selected native lists.
- `:QuickReviewHide` and `:QuickReviewShow` control source inline marks.
- `:QuickReviewHover` shows the note attached to the current qf row.

The qf buffer remains native and unmodifiable. Use the note mapping (default
`<leader>rn`), `a`, or `:QuickReviewAdd` on a qf row instead of editing its
rendered text. Annotated producer rows retain their native text and receive a
triangle; the full note is available through hover or `:QuickReviewHover`.
Qf annotations are also mirrored into the owned review list.

Configure qf indicators and note floats independently:

```lua
require("quickreview").setup({
  quickfix = {
    inline = true,
    float = { enabled = true, delay = 500, command = true },
  },
})
```

## Data Model

Annotations are stored in `item.user_data.quickreview`; producer item fields,
producer text, list context, and unknown metadata are preserved. Owned review
entries are normal valid quickfix items with real `filename`, `lnum`, and
`end_lnum` fields.

The annotation shape is:

```lua
item.user_data.quickreview = {
  version = 1,
  id = "stable-id",
  text = "Full multiline note",
  created_at = 1786920000,
  updated_at = 1786920000,
  location = {
    root = "/repo",
    path = "lua/example.lua",
    line = 10,
    line_end = 12,
    side = "new",
    revision = nil,
    hash = nil,
    resolver = "normal",
  },
}
```

## Export

The default Markdown formatter emits one native-list item per bullet and keeps
native order:

```markdown
- `lua/example.lua:10` - Explain this condition
- `lua/other.lua:20-24` - Existing diagnostic text
```

For annotated items, export uses the note text. Unannotated items use their
native producer text. The original producer text remains unchanged on the
native producer list. To select another producer field or intentionally combine
both values, pass the export `text(item, note, text)` callback.

Formatters and destinations are independent. The Lua API accepts an explicit
list identity:

```lua
require("quickreview").export({
  list = { kind = "quickfix", id = 42 },
  format = "markdown",
  destination = "clipboard",
  prefix = "# Review\n\n",
})
```

Markdown exports also accept optional `prefix` and `suffix` strings. For
custom formatter and resolver contracts, see
[`docs/integrations.md`](docs/integrations.md).

Use `text` when a producer stores its useful message in another field or when
you want note-only output:

```lua
require("quickreview").export({
  text = function(item, note)
    return note and note.text or item.user_data and item.user_data.message or item.text
  end,
})
```

Built-in destinations are `clipboard`, `file`, and optional `sidekick` from
quickfix-export.nvim.

See [`docs/integrations.md`](docs/integrations.md) for resolver, picker,
formatter, destination, and quickfix integration contracts.

## Local Manual Testing

From this repository, launch Neovim with all four sibling repositories on the
runtime path:

```sh
nvim -u test/manual_init.lua
```

This loads `quickfix-persist.nvim`, `quickfix-export.nvim`,
`quickfix-actions.nvim`, and QuickReview from `~/projects`. For another
checkout location, use the `QUICKFIX_ACTIONS_PATH`, `QUICKFIX_EXPORT_PATH`, and
`QUICKFIX_PERSIST_PATH` variables with the headless test scripts.

## Persistence

`quickfix_persist` is optional for annotation and export behavior. When it is
available, the owned review list is automatically saved as
`quickreview/review` using a repository and branch-aware scope. Scope is
rechecked on directory changes, focus regain, shell commands, and supported
Git-plugin events. Explicit save/load operations can persist arbitrary qf and
location lists, but transient producer lists are never watched automatically.

Run tests with:

```sh
nvim --headless -u NONE -l test/run.lua
nvim --headless -u NONE -l test/run_with_persist.lua
```
