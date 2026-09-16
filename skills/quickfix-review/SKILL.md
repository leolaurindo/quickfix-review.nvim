---
name: quickfix-review
description: Use only when the user explicitly asks to write review notes to Quickfix Review, qf-review, or Neovim, or when a Sidekick message explicitly requests a Quickfix Review response; produce importable, versioned JSON.
---

# Quickfix Review

Use this skill only when the user explicitly requests Quickfix Review output, such
as "write notes to Quickfix Review", "use qf-review", or "write review notes to
my Neovim". A generic request for a code review does not activate this skill and
must not create Quickfix Review files. A Sidekick message that explicitly asks
for a Quickfix Review response is also an explicit request.

## Workflow

1. Identify the repository root and comparison range.
2. Inspect the diff and relevant surrounding code.
3. Trace changed data through callers, error paths, persistence, and tests.
4. Report only actionable issues introduced or exposed by the changeset.
5. When Sidekick requests an automatic response, write one complete payload and its ready marker as described below. Otherwise, prefer `.quickfix-review/agent-response.json` when it is unused, or choose another user-visible JSON path.
6. When the automatic response mailbox is not in use, ask the user to run `:QuickfixReviewImport` for the default path or `:QuickfixReviewImport <path>` for another path.

Do not modify source code unless separately asked. Do not report style choices,
pre-existing behavior, or unsupported speculation.

## Automatic responses

The Sidekick message contains a section headed `Quickfix Review notes for this
review:` and ending at `End of Quickfix Review notes.`. That delimited section is
the user's review notes for this request. Review the notes in that section;
conversation outside it is not part of the Quickfix Review payload. Different
requests may cover different files or chunks; the response file is only the
return channel, not a task database.

When instructed to use the automatic response mailbox:

1. Produce exactly one complete version 1 findings payload for the current
   batch; do not split one answer across multiple payloads.
2. Create `.quickfix-review` if needed. The receiving plugin does not create the
   mailbox directory; the first agent writing a response owns its creation.
3. Use `.quickfix-review/agent-response.json` when it does not exist. If it
   exists, do not modify it: choose an unused filename by adding a unique prefix
   before `agent-response.json`.
4. Write the complete payload first. After that write finishes, create an empty
   file at `<payload-path>.ready`. Do not create the marker before the payload is
   complete.
5. Treat both files as ephemeral, disposable mailbox messages—not persistent
   agent state. Never append to an earlier response or carry its findings into
   the new payload. Each response stands alone; imported findings are merged by
   Quickfix Review.
6. Quickfix Review consumes and deletes both the payload and ready marker after
   a successful import. Their disappearance confirms success; do not recreate
   them or report a failure for this review request.
7. Report a concern again only when the current review independently finds it;
   do not recreate entries merely because response files are absent.
8. Do not edit `.gitignore`, `.git/info/exclude`, or unrelated repository files
   to support the mailbox.

An empty `findings` array is a valid complete response. Write JSON only, with no
surrounding prose.

## Findings

Use one concrete concern per finding, the smallest useful source range, and
severity `critical`, `high`, `medium`, or `low` when applicable. Set `confidence`
between 0 and 1 and order findings by severity, then location.

```json
{
  "version": 1,
  "origin": "agent",
  "findings": [
    {
      "path": "relative/path.lua",
      "line": 10,
      "line_end": 12,
      "text": "A concise, actionable review note.",
      "severity": "high",
      "confidence": 0.94,
      "category": "correctness",
      "evidence": "The failure path skips cleanup.",
      "suggestion": "Run cleanup before returning the error."
    }
  ]
}
```

Required fields are top-level `version`, `origin`, and `findings`, plus
`path` and `text` for each finding. `line` and `line_end` are optional for file
findings. Set `origin` to `agent`, use repository-relative paths and positive
1-based lines. Omit IDs; Neovim assigns internal note identity. An empty findings array is valid.
Do not include absolute paths outside the repository, prose outside the JSON, or
executable content.
