#!/bin/sh
set -eu

status=0
max_lines=120
max_words=1000

for file in skills/*/SKILL.md; do
  [ -f "$file" ] || continue

  if ! awk -v file="$file" '
    NR == 1 {
      if ($0 != "---") error("missing opening delimiter")
      next
    }

    !closed && $0 == "---" {
      closed = 1
      next
    }

    !closed && ($0 ~ /^[[:space:]]/ || $0 == "") { next }

    !closed {
      if ($0 !~ /^[[:alnum:]_-]+:[[:space:]]*[^[:space:]].*$/) {
        error("invalid frontmatter line; use key: value or an indented continuation")
        next
      }
      key = substr($0, 1, index($0, ":") - 1)
      fields[key] = 1
    }

    function error(message) {
      print file ": " message > "/dev/stderr"
      failed = 1
    }

    END {
      if (!closed) error("missing closing delimiter")
      if (!fields["name"]) error("missing name")
      if (!fields["description"]) error("missing description")
      exit failed
    }
  ' "$file"; then
    status=1
  fi

  lines=$(wc -l < "$file")
  words=$(wc -w < "$file")
  if [ "$lines" -gt "$max_lines" ] || [ "$words" -gt "$max_words" ]; then
    printf 'WARNING: %s is large (%s lines, %s words; limits are %s/%s)\n' \
      "$file" "$lines" "$words" "$max_lines" "$max_words"
  fi
done

exit "$status"
