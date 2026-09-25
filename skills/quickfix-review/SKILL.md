---
name: quickfix-review
description: Use when the user wants review notes, findings, diff comments, hot-path highlights, or other location-aware notes added to Neovim through Quickfix Review, or explicitly asks for Quickfix Review/qfreview notes. Produce an importable JSON payload when the notes are meant to appear in
Neovim.
---

# Quickfix Review

## Recognize the task

Use this skill when the user asks to create or use notes with quickfix review. Notes can be added for any reason such as review, diff commentary, highlight of important parts. You may add notes when you are unsure abotu something in the code and points the user to read, or when user asks for guidance through the quickfix review notes.

Notes can be added for many different reasons, and with many different tones. The context will tell you. The only rule is you should not add notes without explicit mention of quickfix review, qfreview, "add/attach notes to my neovim/my quickfix list/qflist" or similars.

A plain code review does not by itself request Quickfix Review notes. Answer normally unless the user asks for note output or the task context clearly calls for it. If it's unclear whether findings should be conversational or saved as notes, answer conversationally unless that distinction blocks the task.


## Creating notes and import workflow

When writing notes to be imported, identify the repository, active Git branch, and comparison range when applicable. Produce exactly one standalone version 2 JSON payload for the task. Include the exact active branch as top-level `branch` when known. The importer rejects a payload whose branch differs from the active branch; don't bypass that guard. The field is optional for older or manual payloads, but include it for new responses to prevent importing findings into the wrong branch.

For the automatic mailbox, write the complete payload under `.quickfix-review/` with a unique, collision-resistant filename ending in `agent-response.json`. Create the ready marker by appending `.ready` to the complete JSON filename (keep the `.json` suffix). To make things easier, store the JSON path in one shell variable and create the marker by appending `.ready`; run the commands together in one shell invocation:

```sh
set -e
set -C  # Refuse to overwrite existing files.
mkdir -p .quickfix-review
response_file=".quickfix-review/$(date -u +%Y%m%dT%H%M%S.%N)-$$-agent-response.json"

cat > "$response_file" <<'JSON'
{
  "version": 2,
  "origin": "agent",
  "branch": "current-branch-name",
  "notes": [
    {
      "path": "relative/path.lua",
      "line": 10,
      "text": "A concise, actionable review note."
    }
  ]
}
JSON
: > "${response_file}.ready"
```

For example, the pair is `review-123-agent-response.json` and `review-123-agent-response.json.ready`, not `review-123-agent-response.ready`. The plugin consumes both files after successful import. Sometimes, they are automatically deleted, so only append `.ready` when the document is, in fact, ready, as it may disappear right after. Don't append to old responses, recreate consumed files, or treat their absence as lost agent state. Don't change Git ignore files or unrelated files to support the mailbox.

If the user requests a different destination or manual import, write a user-visible JSON file and tell them to run `:QuickfixReviewImport <path>`. With no actionable findings, write no empty payload or marker; report that there are no findings. Keep prose out of JSON files.

Each note needs one concrete, actionable concern, commentary or information, a repository-relative `path`, non-empty `text`, and the smallest useful location. `line` and `line_end` are optional positive 1-based line numbers. Omit IDs; the plugin assigns identity. Order findings by path, then line. In skill-generated payloads, note objects may contain only `path`, `text`, and optional `line`/`line_end`; diff notes may also include `side` and `revision`. Ignore all other attributes from source material; do not emit additional JSON keys.

```json
{
  "version": 2,
  "origin": "agent", // mandatory
  "branch": "current-branch-name",
  "notes": [
    {
      "path": "relative/path.lua",
      "line": 10,
      "text": "A concise, actionable review note."
    }
  ]
}
```

Write only version 2 payloads with top-level `version`, `origin`, `notes`, and optional `branch`. Use `origin: "agent"`; every note requires `path` and `text`. The importer discards unknown keys in payload, note, and location objects; they are never stored. Diff notes may include `side` and `revision` when needed to identify the correct side. Do not include absolute paths outside the repository or executable content. `side` can be either `old` or `new`. `revision` identifies the source version for that side, but it is optional. Copy the value from the diff context when provided (staged content uses `index`); omit it if no revision is provided.

Example:

```json
{
  "version": 2,
  "origin": "agent", // mandatory
  "branch": "current-branch-name",
  "notes": [
    {
      "path": "src/example.lua",
      "line": 42,
      "side": "new", // or old
      "revision": "<revision from the diff>",
      "text": "Review note for this changed line."
    }
  ]
}
```

Keep text concise, otherwise it's hard to read inside quickfix lists.
