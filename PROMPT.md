# PROMPT.md — Handoff spec for `reviewnotes.nvim`

This file is a complete specification for another model (or engineer) to take over
`reviewnotes.nvim`. Read every section; it describes what the plugin must do, what is
already built, what specifically is wrong or not meeting expectations, and exactly where
the relevant code lives.

---

## 1. Product goal (one paragraph)

A local-only Neovim plugin that lets the user **write comments on lines of any file or
diff buffer, accumulate many comments across different locations, and then export them
as markdown** (default: to the clipboard) so they can paste the whole batch into an AI
agent. It is NOT a PR-review / cloud tool. There are **no comment "types"** (no
COMMENT/ISSUE/PRAISE labels) — every note is just free text attached to a location.

The core loop is:

```
buffer + resolver → normalized location {root, file, line, line_end, side, revision, hash}
  → note store (in-memory + per-repo/branch JSON)
  → render to markdown
  → send via a pluggable "sender" (clipboard / file / sidekick)
```

Two workflows must both work:
1. **Accumulate**: press key → type note → it's stored + rendered inline. Repeat across
   locations. Later `:ReviewExport` sends ALL stored notes at once.
2. **Instant**: `:ReviewSend` sends just the note at the current cursor location.

---

## 2. Where the code lives (all full paths)

Plugin repo: `/home/leo/projects/reviewnotes.nvim/`

| File | Role |
|---|---|
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/init.lua` | Setup, commands, keymaps, branch-change reload, wired actions |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/config.lua` | `setup()` opts, keymap defaults, list backend |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/resolver.lua` | Resolver registry: `register()`, `detect()`, `location()`, `range_location()` |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/resolvers/normal.lua` | Plain file buffers + `:InlineDiff` (same buffer) — `renderable = true` |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/resolvers/native.lua` | `vim.wo.diff` windows — `renderable = true` |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/resolvers/codediff.lua` | codediff.nvim diff buffers — `renderable = true` (re-renders on User events) |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/resolvers/differ.lua` | differ.nvim `differ://` buffers — `renderable = false` |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/resolvers/diffs.lua` | diffs.nvim `diffs://` buffers — `renderable = false` |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/resolvers/neogit.lua` | neogit status / commit view — `renderable = false` |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/store.lua` | In-memory notes + per-repo/branch JSON persistence |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/render.lua` | Markdown renderer (`path:line - text`) |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/marks.lua` | **Inline rendering** of notes as boxed EOL virt_text |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/ui.lua` | Floating note editor |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/picker.lua` | `:ReviewList` backends: quickfix / snacks / telescope / mini |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/sender.lua` | Sender registry: `register()`, `set_default()`, `send()` |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/senders/clipboard.lua` | Default sender → system clipboard |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/senders/file.lua` | Write markdown to a file |
| `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/senders/sidekick.lua` | Send into sidekick.nvim AI CLI |

Config wiring (how it's installed in the user's Neovim):

| File | Role |
|---|---|
| `/home/leo/.config/nvim/lua/plugins/git.lua` (lines ~504-521) | lazy spec: `dir = "~/projects/reviewnotes.nvim"`, `main = "reviewnotes"`, `setup({ send = "clipboard", list = "snacks", keys = {…} })` |
| `/home/leo/.config/nvim/lua/plugins/init.lua` (line ~76) | `"reviewnotes"` added to `ordered_repos` |

---

## 3. What already works (do not break these)

- **Normal-buffer location resolution** including `:InlineDiff` (inline-diff renders on the
  real file buffer, so the `normal` resolver covers it for free).
- **Resolvers** for codediff, differ, diffs.nvim, neogit, native diff, normal. Detection is
  priority-ordered and `pcall`-safe; failures degrade to `normal`.
- **Visual range notes**: `:ReviewNote` accepts a range (`range = true`, `'<,'>`), and
  `<leader>rn` in visual mode resolves `vim.fn.line("'<")`/`line("'>")`. Range notes store
  `line` (start) + `line_end` (end).
- **Persistence**: per repo + branch (or short-hash when detached), JSON under
  `vim.fn.stdpath("data")/reviewnotes/<repo_id>-<branch>.json`. Auto-save on every
  add/update/delete, auto-load on setup + on branch checkout (neogit `User` events) +
  `DirChanged`. **No manual save is needed.** Confirmed working.
- **Float editor** (`ui.lua`): uses `filetype = "text"` (NOT `"markdown"`) — this was a fix
  for cursor "blinking" caused by render-markdown.nvim re-rendering the float on every
  keystroke. Do NOT revert to markdown filetype.
- **Senders** registry + clipboard/file/sidekick; `:ReviewSend`, `:ReviewExport`,
  `:ReviewExportAndClear`, `:ReviewClear`.
- **`:ReviewQf`** (`M.list_quickfix`) always sends to the quickfix list regardless of the
  configured `list` backend. The quickfix text is `path:line  comment` and `<Enter>` jumps.
- **No type system**: no `[COMMENT]`/`[ISSUE]` labels anywhere. Notes are `{id, created_at,
  file, line, line_end, side, revision, hash, text}`.

---

## 4. The exact behaviors the user wants (the crux — read carefully)

These are the requirements that were iterated on and are NOT yet landing correctly. They
are the reason this handoff exists.

### 4.1 Inline rendering — a box, ON THE SIDE of the line, NOT below

- Each note renders as a **single-line box sitting at the end of its annotated line**
  (end-of-line virt_text, `virt_text_pos = "eol"`), so it takes **zero vertical space**
  and does NOT push subsequent lines down.
- The box must look like `╭ note text ╮` (rounded corners on the left and right of the
  same line), with:
  - **Border** (`╭` and `╮`): bright color **derived from the current theme's accent**
    (not hardcoded). It should re-tint when the colorscheme changes.
  - **Text inside**: **normal foreground** (`Normal` / no background), readable, NOT the
    accent color.
- A gutter **sign `»`** in the same accent color marks the line.
- Long notes truncate (e.g. ~32 chars) with `...`.
- This is a single-line EOL annotation — the user explicitly rejected the previous
  multi-line `╭───╮ / │ text │ / ╰───╯` block that appeared BELOW the line (took vertical
  space). "I prefer By side."

Current implementation: `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/marks.lua`
`M.render()` — verify it matches this exactly (single-line `╭ text ╮` at EOL, accent
border, normal text).

### 4.2 Visual mode — box anchored at the BOTTOM (or top) of the selection

- Making a note over a **visual selection** (range note, `line`…`line_end`) must render
  the box at the **bottom** of the selection (i.e. anchored at `line_end`). Currently the
  `normal` resolver's `anchor()` returns `line_end` for ranges; ensure the box visually
  appears at the last selected line.
- The current `marks.lua` `anchor_line()` and `resolvers/normal.lua:anchor()` both already
  return `line_end` for ranges — verify end-to-end that the box shows at the bottom line of
  a visual selection.

### 4.3 Snacks list — comment must be VISIBLE in the list row, NOT as a preview title

The user is happy with the snacks picker for `:ReviewList` (config sets `list = "snacks"`).
Requirements:

- **The comment must NOT appear as the preview window's title/header.** It previously
  leaked into the preview border via `item.preview_title` — that is wrong. The preview
  title should stay as the file name (`app.lua`), like normal file previews.
- **The comment text must be visible in the LIST ROW itself.** The desired layout matches
  how **snacks' git_log picker renders metadata on the right side** of a row
  (`Snacks.picker.util.align(text, width, { align = "right", truncate = true })`): location
  on the left, comment **right-aligned** on the same row. If right-align proves impossible,
  put the comment on the left after the location — the hard requirement is that the comment
  text is plainly visible in the row, and that the file preview (right pane) still works.
- Keep the file preview (`preview = "file"`) and the ability to jump to the note on
  confirm.
- If not able to place in the left side list row, make it appear as a "header block" similar as how Snacks renders metadata of commits on its "git log" picker on top of the right-side preview.

Current implementation: `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/picker.lua`
`snacks()` — uses a custom `format` function with `Snacks.picker.util.align(…, {align="right"})`
and NO `preview_title`. Verify it renders `location  …comment` and the preview title is the
file, not the comment.

### 4.4 Float editor must not blink

Keep `filetype = "text"` in `/home/leo/projects/reviewnotes.nvim/lua/reviewnotes/ui.lua`.
Do not reintroduce `markdown`.

---

## 5. Reference: snacks.nvim internals used by `picker.lua`

Read these in `/home/leo/.local/share/nvim/lazy/snacks.nvim/lua/snacks/picker/`:

- **`config/init.lua`**: `opts.format` can be a function `(item, picker) → Highlight[]`;
  `opts.preview` can be a string (`"file"`) or function.
- **`preview.lua`** around line 90: preview title resolves `ctx.item.preview_title or
  ctx.item.title`, then falls back to the file basename. **Set neither** (or set
  `preview_title = nil`) so the title stays the filename.
- **`format.lua`** `M.file(item, picker)` (line ~143) and `M.git_log(item, picker)`
  (line ~213): shows the pattern for rendering a row and for right-aligning metadata with
  `Snacks.picker.util.align`.
- **`util/init.lua`** `M.align(text, width, opts)` (line ~157): `opts.align = "right"` pads
  left so text is right-aligned; `opts.truncate = true` truncates with `…`.
- **`core/list.lua`** `_render` (line ~523): `text:gsub("\n", " ")` — items are rendered as
  a **single line**; a literal two-line block per item is NOT natively supported. Prefer a
  single row with right-aligned comment.

---

## 6. Commands & keymaps (final contract)

All commands are created in `init.lua:setup()`.

| Command | Key | Action |
|---|---|---|
| `:ReviewNote` | `<leader>rn` (n + v) | Add note at location (range = visual selection) |
| `:ReviewSend` | `<leader>rs` | Send note at cursor via active sender |
| `:ReviewExport` | `<leader>re` | Render all notes → sender (clipboard default) |
| `:ReviewExportAndClear` | `<leader>rx` | Export then clear |
| `:ReviewClear` | `<leader>rc` | Clear current branch store |
| `:ReviewList` | `<leader>rl` | List via configured backend (snacks) |
| `:ReviewQf` | — | Always send notes to quickfix list |
| `:ReviewHide` / `:ReviewShow` | — | Toggle inline box rendering |

Config: `/home/leo/.config/nvim/lua/plugins/git.lua:504` sets `send = "clipboard"`,
`list = "snacks"`, keys as above.

---

## 7. Acceptance criteria (how to verify)

Use a scratch git repo and a real tmux/terminal (headless `nvim --headless` does NOT fire
buffer-local insert-mode mappings reliably; verify interactively or via a tmux session):

1. `:ReviewNote` in a normal file → float opens with NO cursor blinking → type → `<Esc>`
   (or `q` or `<C-s>`) → note saved; `»` gutter sign appears and a **single-line
   `╭ text ╮` box sits at EOL on that line**; buffer line count unchanged (no vertical
   space added).
2. Visual-select lines 2-4 → `:ReviewNote` → type → save → box appears at the **bottom**
   (line 4).
3. `:ReviewList` (snacks) → the row shows the **location on the left and the comment text
   visibly** (right-aligned preferred); the preview pane title is the **filename**, not the
   comment; preview shows the file content at that line; `<CR>` jumps to the note.
4. `:ReviewQf` → quickfix opens with `path:line  comment` rows; `<Enter>` jumps.
5. Close nvim, reopen in same repo/branch → notes still present (persistence). Switch
   branch → store is empty; switch back → notes return.
6. `:ReviewExport` → clipboard contains markdown with `- \`path:line\` - comment` lines.
7. `:lua require("reviewnotes")` loads without error in the real config; `stylua` and
   `luacheck` clean (config: `/home/leo/projects/reviewnotes.nvim/.luacheckrc` sets
   `globals = { "vim" }`, `unused_args = false`).

---

## 8. Style / engineering constraints (from the user)

- **Keep it minimal and elegant.** No over-engineering. One-liners preferred. Builtin
  solutions first. The user values readable, low-cognitive-effort code.
- **Do not add comment types/labels.** No PR/cloud features.
- **Do not add a `plugin/` file or external dependencies** — everything is `lua/reviewnotes/`.
- **`renderable = false` resolvers** (differ, diffs, neogit) get no inline box (their
  plugins re-render the buffer and wipe extmarks); notes there are still stored, listed,
  and exported — resolution and export must work everywhere.
- Run `stylua` and `luacheck` on every change.
