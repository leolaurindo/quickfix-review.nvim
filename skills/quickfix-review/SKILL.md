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

1. Identify the repository root, comparison range, and active Git branch. Include
   that branch in the response payload so a delayed response cannot be imported
   into a different branch's review scope.
2. Inspect the diff and relevant surrounding code.
3. Trace changed data through callers, error paths, persistence, and tests.
4. Report only actionable issues introduced or exposed by the changeset.
5. If there are findings and Sidekick requests an automatic response, write one complete payload and its ready marker as described below. Otherwise, save the non-empty payload to `.quickfix-review/agent-response.json` when unused, or choose another user-visible JSON path.
6. When the automatic response mailbox is not in use, ask the user to run `:QuickfixReviewImport` for the default path or `:QuickfixReviewImport <path>` for another path. Do not ask for import when there are no findings.

Do not modify source code unless separately asked. Do not report style choices,
pre-existing behavior, or unsupported speculation.

## Automatic responses

The Sidekick message includes the formatted review notes supplied by the user.
Treat those notes as the review scope; do not assume the message has fixed
Quickfix Review delimiters. Include any explicit question or implementation
request in scope; modify source only when separately authorized. Different
requests may cover different files or chunks; the response file is only the
return channel, not a task database.

When instructed to use the automatic response mailbox:

1. For a non-empty result, produce exactly one complete version 2 notes
   payload for the current batch; do not split one answer across multiple payloads.
2. Create `.quickfix-review` if needed. The receiving plugin does not create the
   mailbox directory; the first agent writing a response owns its creation.
3. Use a collision-resistant, shell-generated prefix (UTC timestamp with
   sub-second precision plus the shell PID) before `agent-response.json`, and
   check both candidate paths before use. For example:

   ```sh
   prefix="$(date -u +%Y%m%dT%H%M%S.%N)-$$"
   path=".quickfix-review/${prefix}-agent-response.json"
   while [ -e "$path" ] || [ -e "$path.ready" ]; do
     prefix="${prefix}-x"
     path=".quickfix-review/${prefix}-agent-response.json"
   done
   ```

4. Write one complete payload to the selected path without appending or
   overwriting an existing file. After the write finishes, create an empty file
   at `<payload-path>.ready`. Do not create the marker before the payload is
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

When there are no actionable findings, do not write a payload or ready marker;
report directly to the user that there are no findings. This avoids making an
empty mailbox look like a failed response. For non-empty results, write JSON
only, with no surrounding prose.

## Findings

Use one concrete concern per finding, the smallest useful source range, and
severity `critical`, `high`, `medium`, or `low` when applicable. Set `confidence`
between 0 and 1 and order findings by severity, then location.

```json
{
  "version": 2,
  "origin": "agent",
  "branch": "current-branch-name",
  "notes": [
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

Required fields are top-level `version`, `origin`, and `notes`, plus
`path` and `text` for each note. Include top-level `branch` with the exact active
branch name as an import guard; it is optional for older/manual payloads. `line`
and `line_end` are optional for file notes. Set `origin` to `agent`, use
repository-relative paths and positive 1-based line numbers. Omit IDs; Neovim
assigns internal note identity. Emit only version 2 payloads with a top-level
`notes` array; version 1 `findings` payloads are rejected.
Do not include absolute paths outside the repository, prose outside the JSON, or
executable content.
