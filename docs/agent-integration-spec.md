# Agent Response Mailbox Specification

Issue: [#1 — Add bidirectional agent integration](https://github.com/leolaurindo/quickfix-review.nvim/issues/1)

Status: implemented on `spec/issue-1-agent-integration`

## Goal

Make the existing Sidekick and findings-import workflow automatic without
creating synchronized state or a second note database.

The Sidekick message explicitly delimits the selected notes between
`Quickfix Review notes for this review:` and `End of Quickfix Review notes.`.
That section is the user's review payload. The response file is only a return
channel; it is not a synchronized task database.

## User workflow

1. The user writes notes and runs `:QuickfixReviewSendAgent`.
2. Sidekick receives the selected notes plus concise response instructions.
3. The agent writes one complete response to
   `.quickfix-review/agent-response.json`, or an unused prefixed variant when
   that path exists, then creates a matching `.ready` file.
4. Quickfix Review validates and merges each ready response into its owned native
   quickfix list.
5. After successful import, the response and marker are deleted. Their
   disappearance confirms successful consumption, not failure. Agent findings
   display a colored `AGENT` badge.

`:QuickfixReviewSendAgent!` submits immediately for that invocation. Without
`!`, Sidekick inserts the message so the user can inspect and submit it.

Incremental review works by sending separate batches. Each response contains
only findings from its batch; importing it never replaces the whole Quickfix
Review list.

## Response mailbox

The default payload and completion marker are:

```text
.quickfix-review/agent-response.json
.quickfix-review/agent-response.json.ready
```

If the default payload already exists, the agent chooses an unused filename by
adding a unique prefix before `agent-response.json`. Each payload is one response,
not a persistent findings database.

The agent must:

- write exactly one complete version 1 findings payload;
- never modify an existing response file; use an unused prefixed filename instead;
- create an empty `<payload-path>.ready` marker only after the payload write finishes;
- treat both files as ephemeral, disposable mailbox messages, not persistent state;
- never append to or incrementally build the response;
- never copy findings from an earlier response merely because they used to be present;
- know that Quickfix Review deletes both files after successful import, and that
  their disappearance confirms success rather than failure; and
- report a concern again only when the current review independently finds it.

Quickfix Review must:

- watch the parent directory for ready markers;
- validate through the existing findings importer and repository scope checks;
- assign internal IDs and merge valid findings through the existing importer;
- delete both files only after import succeeds;
- remove the marker but retain an invalid response for inspection and correction;
- never interpret absence as deletion; and
- never delete an imported note merely because it is absent from a later batch.

Deleting or editing a note in Quickfix Review does not rewrite the mailbox or
send state to the agent. A consumed response cannot replay after a user deletion.
A later review may independently report the same concern again; that is a new
finding decision, not mailbox reconstruction.

## Payload

The mailbox uses the existing import schema:

```json
{
  "version": 1,
  "origin": "agent",
  "findings": [
    {
      "path": "lua/example.lua",
      "line": 20,
      "line_end": 22,
      "text": "Cleanup is skipped on this return.",
      "severity": "high",
      "confidence": 0.95,
      "category": "correctness",
      "evidence": "The return precedes close().",
      "suggestion": "Close the handle before returning."
    }
  ]
}
```

`version`, `origin`, and `findings` are required. `origin` must be `agent` for
the automatic path. Each finding requires a repository-relative `path` and
non-empty `text`; agents omit IDs and Neovim assigns internal identity from the
payload fingerprint and finding position. Paths escaping the active repository
lexically or through symlinks are rejected. Invalid findings
are skipped and reported using existing partial-merge behavior.

An empty findings array is a valid complete response and is consumed without
deleting existing notes.

## Configuration and commands

Enabled by default; set `agent.response.watch = false` to opt out:

```lua
require("quickfix_review").setup({
  agent = {
    protect_git = true,
    response = {
      watch = false,
      path = ".quickfix-review/agent-response.json",
    },
  },
  quickfix = {
    agent_label = { enabled = true, text = " AGENT " },
  },
})
```

Commands:

- `:QuickfixReviewSendAgent[!]` sends user-authored review notes through
  Sidekick; `!` submits immediately.
- `:QuickfixReviewSendAgentAndClear[!]` sends them and clears all selected notes
  only after a successful send.
- `:QuickfixReviewClearAgent` clears agent-authored notes in the active scope.
- `:QuickfixReviewReloadAgentResponse` explicitly retries a retained response.
- `:QuickfixReviewImport [file]` remains the manual fallback and defaults to the configured repository response path.

Direct Sidekick response callbacks, Neovim RPC, headless runners, request files,
state synchronization, tombstones, and deletion protocols are deferred. They
should be separate proposals if the mailbox workflow proves insufficient.

## Git safety

The mailbox is inside the repository so sandboxed agents can write it. Before
watching, Quickfix Review checks it with `git check-ignore --no-index` and,
when needed, adds `/.quickfix-review/` to the repository-local
`.git/info/exclude`.

It does not edit tracked `.gitignore` or global Git configuration. Local
exclusion is best-effort: if it cannot be established, the watcher continues
and warns that the user should ignore the path manually. `protect_git = false`
skips the attempt and warns that the path is visible to Git.

## Visual provenance

The existing extmark renderer is extended rather than replaced. Agent-authored
notes show a colored ` AGENT ` virtual-text badge in producer and owned native
quickfix/location-list rows. It uses `QuickfixReviewAgent`, linked by default to
`DiagnosticHint`, with `hl_mode = "combine"` for selected rows.

The badge never changes item text, producer metadata, list order,
`quickfixtextfunc`, or ordinary exports. User notes retain the existing glyph.

## Tests

Coverage includes:

- Sidekick send and one-off submit;
- explicit response-mailbox instructions in the sent message;
- incomplete payloads remaining inert until marked ready;
- multiple ready responses and successful consumption;
- repository-local Git exclusion;
- repository and symlink path validation;
- stable-ID merge summaries; and
- colored badges in the owned quickfix list.

All existing headless tests, `test/run_agent.lua`, `luacheck lua test`, help-tag
generation, and `git diff --check` are release gates.

## Estimated net LOC

Net LOC means added lines minus deleted lines, excluding this specification.

| Area | Estimated net LOC |
| --- | ---: |
| Mailbox watcher, stable writes, consumption, and Git protection | +180 |
| Sidekick one-off send and response instructions | +35 |
| Import hardening and merge summaries | +35 |
| Agent provenance badge | +30 |
| Tests and user documentation | +180 |
| **Total** | **+460** |

Expected range: **+380 to +550 net LOC**.

## Acceptance criteria

- Normal use requires one send command and no import command.
- Sidekick carries the selected review notes directly; no request or state file
  is created.
- The agent writes one complete response and never accumulates prior batches.
- A valid response is imported once and then deleted.
- Invalid responses remain available for correction.
- Incremental batches merge without replacing unrelated findings.
- Agent notes are visually distinct in native quickfix/location-list rows.
- Git protection is attempted by default and failures warn without stopping the watcher.
