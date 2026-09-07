# QuickReview Plan

The current runtime uses native quickfix and location lists as the source of
truth. Notes live in `item.user_data.quickreview`; producer fields remain
unchanged. Persistence is provided by `quickfix_persist` and is optional.

The four-plugin architecture is implemented and documented in
[`SPINOFF.md`](SPINOFF.md):

1. `quickfix-actions.nvim` owns native list actions and qf UI lifecycle.
2. `quickfix-export.nvim` owns generic formatting and destinations.
3. `quickfix-persist.nvim` remains note-agnostic.
4. `quickreview.nvim` owns annotations, resolvers, marks, owned review lists,
   and note-aware UI.

The remaining work in this plan is product decisions, compatibility validation,
and small behavior fixes—not another plugin extraction.

## Repository And Test Layout

Each plugin lives in an independent repository under `~/projects/quickplugins`:

```text
~/projects/quickplugins/quickfix-actions.nvim
~/projects/quickplugins/quickfix-export.nvim
~/projects/quickplugins/quickfix-persist.nvim
~/projects/quickplugins/quickreview.nvim
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
commands remain under `QuickReview...`. Commands are thin user-facing wrappers,
not an inter-plugin compatibility API. Current command names and core behavior
are covered by characterization tests; mapping coverage and defaults remain part
of the Quicker compatibility work. Mapping installation remains configurable so
Actions can coexist with Quicker.

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
- Editable qf `:write` support remains deferred and is not part of the compatibility contract.

## Completed And Remaining Work

Completed:

1. Characterization and integration tests cover native lists, annotations,
   command registration and core behavior, export, import, and optional
   persistence.
2. Qf UI lifecycle, target resolution, list reads, current-entry lookup,
   replacement, deletion, and clearing live in Actions.
3. Normalized export records, formatters, and destinations live in Export.
4. QuickReview consumes the required Actions and Export Lua APIs without
   retaining duplicate generic implementations.

Remaining validation:

1. Test on Neovim 0.10 and current stable Neovim, against a recorded Quicker
   revision, including mapping ownership and metadata preservation.
2. Add coverage for the final formatter, metadata-export, and indicator-display
   decisions below.

Editable qf `:write` support is a separate later milestone. It may be explored
only after the integration suite is stable, and must remain opt-in, disabled by
default, metadata-preserving, stale-list-safe, and disabled when another plugin
owns editable qf buffers.

## Non-Goals

- Do not replace the native qf renderer.
- Do not duplicate Neovim's built-in `[q`, `]q`, `[l`, or `]l` navigation.
- Do not make generic export understand note metadata by default.
- Do not make persistence automatically watch arbitrary producer lists.
- Do not create a second note database.

## Next Product Decisions

This section captures the intended direction for the next iteration. Items marked
as open need agreement before implementation.

### Plugin Name

Evaluate renaming `quickreview.nvim` to `quickfix-review.nvim`, or another name
that makes its relationship to native quickfix and location lists immediately
clear. The selected name should distinguish the plugin's review annotations and
workflow from the generic `quickfix-actions.nvim`, `quickfix-export.nvim`, and
`quickfix-persist.nvim` plugins.

### Export Templates

Open: decide and implement a custom formatter callback API in
`quickfix-export.nvim`, in addition to its named built-in `markdown` and `json`
formatters. The current implementation accepts formatter names only.

```lua
require("quickfix_export").run({
  list = { kind = "quickfix", id = 42 },
  format = function(records, opts)
    return render_template(records, opts)
  end,
})
```

This is preferred over a string placeholder language: a Lua callback can render
any format and make explicit decisions about escaping, ordering, and optional
fields without creating another templating syntax. QuickReview should pass this
formatter option through after it prepares note-aware records.

The template, not list mutation, should decide whether a rendered record shows
the producer's original text, the review note, or both.

### Quickfix Indicator Contrast

Open bug: the annotation triangle at the end of a quickfix row uses virtual
text without combining its highlight with the selected-row highlight. On the
active row, this produces an inconsistent background behind the indicator.
Update the extmark highlight mode to combine with the underlying quickfix
selection highlight, so the indicator remains visible while the selected row
retains one continuous background.

### Annotation Data In Export

Open: determine the appropriate generic export boundary for data stored on
native items. QuickReview can already inspect annotations on any explicitly
selected quickfix or location list, but its records do not currently include
review metadata.

- `quickfix-export.nvim` currently exports a stable normalized record and does
  not expose raw `user_data`.
- Generic consumers may need selected associated data, but exporting arbitrary
  `user_data` by default risks unstable payloads, plugin-private values, and
  non-JSON-safe data.
- QuickReview needs its own exports to include review metadata, especially
  imported fields such as severity, confidence, evidence, and suggestion.
- This must work when exporting any producer quickfix or location list that has
  `user_data.quickreview`, not only the named managed review list.
- Unannotated items should continue to fall back to the normal underlying
  `quickfix-export.nvim` record behavior.

Recommended direction for discussion:

- Keep generic records metadata-free by default.
- Add an explicit generic selector/callback for opt-in associated data if a
  reusable, JSON-safe contract can be defined.
- Have QuickReview add `note.metadata` to its records for every annotated list
  item, while keeping annotation internals such as ID, version, and timestamps
  out unless explicitly requested.
- Let QuickReview JSON and custom formatter callbacks consume that metadata;
  built-in Markdown should remain concise unless configured otherwise.

### Producer And Managed List Display

The managed-list display decision remains open independently from export policy.
The current implementation displays note text only; keep that behavior only if
it is accepted as the public policy.

Confirmed producer-list behavior:

- Never modify the producer's native `item.text`.
- Store the review annotation in `item.user_data.quickreview`.
- Leave the user in the current producer quickfix/location-list window after
  saving.
- Keep the end-of-line annotation indicator and hover preview in that list.
- Do not automatically switch to or open the managed review list.

The remaining managed-list choice is whether an item displays:

1. Note text only.
2. Original producer text followed by note text.
3. Another concise representation chosen explicitly by configuration.

Recommendation: show note text only in the managed review list. It makes that
list a focused review inbox, avoids repeating diagnostic text already available
in the producer list, and keeps the original producer text available in the
copied native item for templates or future display choices. If both are needed,
prefer an explicit display configuration rather than changing the producer
data or adding an interaction mode.

### Annotation Interaction Semantics

The intended and agreed behavior for adding a note to an unannotated producer
quickfix or location-list item is:

1. Open the note editor prefilled with the item's current `text`.
2. Let the user freely edit that text: retain it, replace it, append to it, or
   remove it as appropriate for the review note.
3. Save the editor result as the QuickReview note while leaving the producer
   item unchanged.
4. Add the annotation metadata, render the indicator, and mirror the annotated
   item to the managed review list.

Implementation gap: the current qf-row editor is empty for an unannotated item;
it must be changed to prefill `item.text`. Already annotated items are
prefilled with their existing note text.

For an already annotated item, prefill the editor with the existing note text,
not the producer text. This gives one predictable `add/edit` interaction and
removes append-versus-replace modes and configuration. The note editor's
initial text is the user's only decision point.

Internal terminology cleanup: rename local variables holding
`item.user_data.quickreview` from `note` to `annotation` where practical. This
makes the distinction between the producer's `item.text` and the managed
`annotation.text` explicit. This is an internal readability change only; the
stored `user_data.quickreview` schema and public behavior remain unchanged.

Recommended constraints to retain:

- Do not replace or concatenate the producer's native `item.text`.
- Do not ask the user to choose append or replace before opening the editor.
- Do not auto-open the managed list after annotation.
- Do not make the managed-list display policy determine exported text; formatters
  own that choice.
