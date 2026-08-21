---
name: quickreview-review
description: Review a repository changeset and seed QuickReview with concise, evidence-based findings in versioned JSON.
---

# QuickReview Review

Use this skill when the user wants an AI-assisted code review whose findings
should appear in the QuickReview Neovim list.

## Review Workflow

1. Identify the repository root and the intended comparison range.
2. Inspect the diff and the relevant surrounding code.
3. Follow changed data flow into callers, error paths, persistence, and tests.
4. Report only actionable issues introduced or exposed by the changeset.
5. Write `findings.json` in the repository or another user-visible path.
6. Ask the user to run `:QuickReviewImport <path>` unless a live Neovim import
   mechanism is explicitly available.

Do not modify source code as part of this skill unless the user separately asks
for implementation. Do not create a finding for style preferences, unchanged
pre-existing behavior, or speculative risks without evidence.

## Finding Quality

Each finding should identify one concrete concern. Prefer the smallest source
range that demonstrates it. The `text` is displayed directly in QuickReview,
so make it self-contained and include the impact, evidence, and recommended
direction when useful.

Use these severity values when applicable: `critical`, `high`, `medium`, or
`low`. Set `confidence` between 0 and 1. Order findings by severity and then
by source location.

## Output Contract

Write valid JSON with this shape:

```json
{
  "version": 1,
  "source": "codex",
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

Required fields are `version`, `findings`, `path`, and `text`. `line` and
`line_end` are optional for file-level findings. Use repository-relative paths,
positive 1-based line numbers, and a stable ID based on the issue rather than
the current wording alone. An empty findings array is valid when no actionable
issues are found.

Never include absolute paths outside the repository, generated prose outside
the JSON payload, or executable content in a finding.
