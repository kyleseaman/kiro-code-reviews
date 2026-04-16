#!/usr/bin/env bash
set -euo pipefail

# Annotates a unified diff with absolute file line numbers on each + line.
# Input: raw diff on stdin or file arg
# Output: annotated diff on stdout
#
# Transforms:
#   @@ -10,5 +20,7 @@ function foo()
#   +  const x = 1;
# Into:
#   @@ -10,5 +20,7 @@ function foo()
#   +[21]  const x = 1;
#
# Agents read the [N] annotation instead of computing line numbers from hunk headers.

INPUT="${1:-/dev/stdin}"
FILE=""
LINE=0

while IFS= read -r line; do
  case "$line" in
    "--- "*)
      echo "$line"
      ;;
    "+++ "*)
      # Extract file path (strip +++ b/ prefix)
      FILE="${line#+++ b/}"
      echo "$line"
      ;;
    "@@"*)
      # Parse new-file line number from hunk header: @@ -old,count +new,count @@
      LINE=$(echo "$line" | sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*/\2/')
      echo "$line"
      ;;
    "+"*)
      # Added line — annotate with absolute line number
      echo "+[${LINE}]${line:1}"
      LINE=$((LINE + 1))
      ;;
    "-"*)
      # Deleted line — no line number increment
      echo "$line"
      ;;
    *)
      # Context line — increment line counter
      LINE=$((LINE + 1))
      echo "$line"
      ;;
  esac
done < "$INPUT"
