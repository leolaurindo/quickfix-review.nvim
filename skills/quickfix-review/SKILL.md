---
name: quickfix-review
description: Use when the user asks for a code review and actionable findings should be reported through Quickfix Review; produce importable, versioned JSON.
---

# Quickfix Review

Use this skill when findings should appear in the Quickfix Review list.

## Workflow

1. Identify the repository root and comparison range.
2. Inspect the diff and relevant surrounding code.
3. Trace changed data through callers, error paths, persistence, and tests.
4. Report only actionable issues introduced or exposed by the changeset.
5. Write `findings.json` in the repository or another user-visible path.
6. Ask the user to run `:QuickfixReviewImport <path>` unless live import is available.

Do not modify source code unless separately asked. Do not report style choices,
pre-existing behavior, or unsupported speculation.

## Findings

Use one concrete concern per finding, the smallest useful source range, and
severity `critical`, `high`, `medium`, or `low` when applicable. Set `confidence`
between 0 and 1 and order findings by severity, then location.

```json
{
  "version": 1,
  "source": "codex",
  "origin": "agent",
  "findings": [
    {
      "id": "stable-finding-id",
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
findings. Set `origin` to `agent`, use repository-relative paths, positive
1-based lines, and stable IDs. An empty findings array is valid.
Do not include absolute paths outside the repository, prose outside the JSON, or
executable content.
