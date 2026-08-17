# quickfix-notes.nvim

Annotate entries in any Neovim quickfix or location list, navigate their source
locations, and export the list with its optional notes. Normal files and the
existing diff resolvers are supported.

```lua
require("quickfix_notes").setup({
  send = "clipboard",
})
```

`require("quickfix-notes")` is also supported. The former `reviewnotes` module
and `:Review...` commands remain available during migration.

## Lists

Open any quickfix or location list and use the configured note mapping (default
`<leader>rn`) or `a` to add/edit a note for its current entry. Notes remain in
the plugin store: the producer's list items and metadata are never replaced.
QuickfixNotes also maintains its own `review` quickfix list from the first note.

- `:QuickfixNotesExportList` exports the active quickfix or location list,
  including attached notes.
- `:QuickfixNotesList` opens the owned `review` quickfix list.
- `:QuickfixNotesSaveList <name>` saves the active list through
  `quickfix_persist` and registers it for autosave.
- `:QuickfixNotesLoadList <name>` restores a saved list and registers it for
  autosave.

The persistence commands require `quickfix_persist` on `runtimepath`; all note
and export behavior works without it. With `persist_review_list = true` (the
default), the owned `review` list is saved and restored automatically.

## Migration

Existing data under `stdpath("data")/reviewnotes` is read automatically when no
new snapshot exists. Subsequent note changes write to
`stdpath("data")/quickfix-notes`, leaving the old file untouched.

Run headless coverage with:

```sh
nvim --headless -u NONE -l test/run.lua
```
