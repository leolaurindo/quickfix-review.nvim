# Integrations

The package keeps responsibilities separate:

- `quickfix_persist` stores native list snapshots.
- `quickfix_actions` reads and mutates native lists.
- `quickfix_export` normalizes, formats, and sends records.
- `quickfix_review` resolves note locations, stores notes on producer items, mirrors them into the owned notes quickfix list, and selects note text.

Notes can originate in source buffers, quickfix/location-list rows, or diff rows.
Native list IDs and `user_data.quickfix_review.id` identify them; rendered qf text
is not an API.

## Resolvers

Resolvers are registered under `lua/quickfix_review/resolvers/`:

```lua
return {
  name = "my_diff_ui",
  priority = 50,
  renderable = true,
  detect = function(bufnr, winid) end,
  location = function(bufnr, winid) end,
  range_location = function(bufnr, start_line, end_line) end,
  anchor = function(location, bufnr)
    return location.line_end or location.line
  end,
}
```

`range_location` is needed when UI rows do not map directly to source rows;
otherwise a diff or other transformed row becomes a file-level note. `anchor`
controls the source mark. A resolver that identifies a file but cannot safely map
its rows must not invent line coordinates.
Register a resolver with:

```lua
require("quickfix_review.resolver").register(require("my_resolver"))
```

Built-in adapters cover normal buffers, native diffs, Diffview+, CodeDiff,
Differ, diffs.nvim, and Neogit. Unknown absolute-file URIs receive file-level
notes. Historical-side navigation falls back to the stored worktree path.

## Pickers

`quickfix_review.picker.entries({ source = "owned" })` and
`entries({ source = "current" })` return native targets, note IDs, paths, ranges,
note text, and preview coordinates. The built-in note picker uses Snacks or
`vim.ui.select`; Telescope can consume the same entries without creating an
aggregate list.

`quickfix_review.search(opts)` delegates native list access and row selection to
`quickfix_actions.search()`. It searches all current-list entries by path,
producer text, and attached note text, then focuses the selected native row
without jumping to its source buffer. `quickfix_actions.search()` provides the
same behavior for path and producer text only; its `format_item` option controls
the displayed and searchable text, and `on_confirm` can override selection.

## Export extensions

The pipeline is:

```text
native list -> normalized records -> formatter -> destination
```

Records contain normalized location/text fields, not raw items or note IDs.
Review applies canonical note locations and detached JSON-safe `metadata` to its
records. IDs, versions, and timestamps remain private.

Use a note-aware selector when needed:

```lua
require("quickfix_review").export({
  text = function(item, note)
    return note and note.text or item.user_data and item.user_data.message or item.text
  end,
})
```

Custom formatters receive `(records, opts)` and return a string, including an
empty string, or `nil, err`. Named formatters expose `format(records)`. Custom
destinations expose `name` and `send(payload, opts)`:

```lua
local sender = require("quickfix_review.sender")
sender.register(require("my_destination"))
sender.set_default("my_destination")
```

Built-in formats are Markdown and JSON; destinations are clipboard, file, and
optional Sidekick. Markdown accepts `prefix` and `suffix`, ignores metadata,
and JSON includes it. A rejected formatter or destination prevents sending and
clearing.

`send_agent({ submit = true })` uses the normal Markdown pipeline to send
selected user-authored review notes through Sidekick. General exports also omit
agent notes unless `include_agent_notes = true`; explicit origin filters remain
available. The agent returns one complete existing-schema payload through the
watched `.quickfix-review/agent-response.json` mailbox, creating the mailbox
directory first and using an unused prefixed variant if that path exists, then
creates a matching `.ready` file. The watcher does not create repository files or
modify Git metadata before that first response. Git exclusion is best-effort and
warns on failure. Review imports through the normal merge path
and deletes both files after success. Their disappearance confirms successful
consumption, not failure. The mailbox is not persistent or synchronized state.

## Native list rules

Targets are `{ kind = "quickfix", id = 42 }` or
`{ kind = "location", id = 17, winid = 1001 }`. Location `winid` is the owning
file window. Stale IDs and invalid owners fail. Mutations preserve native title,
context, index, metadata, and `changedtick` checks.

Quickfix buffers remain native and unmodifiable. Review does not own
`quickfixtextfunc`, `BufWriteCmd`, or rendered-row parsing.

## Quickfix Diffs

Review consumes version 1 `item.user_data.quickfix_diffs` without requiring the
producer or parsing `item.text`:

- new-side hunks use new ranges;
- deletion-only hunks use old ranges and source identity;
- full-file items become file-level notes;
- revision and fingerprint labels appear only when needed;
- each Diffs run creates a fresh native list and never reattaches old notes.

For patch-plus-note output, export the producer target and select both values:

```lua
local items, err, target = require("quickfix_diffs").open({
  mode = "head", full_diff = true,
})
assert(items, err)
if target then
  require("quickfix_review").export({
    list = target,
    format = "json",
    text = function(item, annotation)
      return annotation and (annotation.text .. "\n\n" .. item.text) or item.text
    end,
  })
end
```

## Persistence and note lifecycle

Persist is optional. Review watches only its owned list; use `quickfix_persist`
directly for arbitrary named lists. Worktree notes use whole-file fingerprints;
Diffs supplies Git fingerprints. Changed sources produce advisory `stale = true`
records; `warn_stale = false` suppresses notifications and Markdown stale labels.
Re-anchoring updates the same note ID and preserves text, creation time, metadata,
and producer origin. It does not rebase diffs or guess matches.
