#!/usr/bin/env bash
# ABOUTME: Posts AI-generated code review findings as inline comments via GitHub API.
# ABOUTME: Handles summary formatting, verdict labeling, and payload construction.
set -euo pipefail

REVIEW_FILE="/tmp/kiro-review.json"
PR="$PR_NUMBER"

# If no findings file, post a clean review
if [[ ! -f "$REVIEW_FILE" ]]; then
  echo "No review file found — posting clean summary"
  gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}/reviews" \
    -f body="✅ **Kiro Code Review** — No issues found." \
    -f event="COMMENT"
  exit 0
fi

# Validate JSON
if ! jq empty "$REVIEW_FILE" 2>/dev/null; then
  echo "::error::Invalid JSON in $REVIEW_FILE"
  echo "--- File contents ---"
  cat "$REVIEW_FILE"
  echo "--- End of file ---"
  exit 1
fi

FINDING_COUNT=$(jq '.comments // [] | length' "$REVIEW_FILE")

# Build review body (summary + strengths + verdict)
BODY=$(jq -r '
  def verdict_label:
    (.verdict // "no verdict") | ascii_downcase |
    if . == "merge" then "✅ Merge"
    elif . == "merge with fixes" then "Merge with fixes"
    elif . == "needs rework" then "Needs rework"
    else "No verdict" end;

  "🤖 **Kiro Code Review**\n\n" +
  (.summary // "No summary provided.") + "\n\n" +
  (if .strengths and (.strengths | length) > 0
    then "### Strengths\n" + (.strengths | map("- \(.)") | join("\n")) + "\n\n"
    else "" end) +
  "**Verdict: " + verdict_label + "**" +
  (if .verdict_reason and .verdict_reason != "" then " — " + .verdict_reason else "" end) +
  "\n\n---\n*Found \(.comments // [] | length) finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).* · To re-run, go to Actions → Kiro Code Review → Run workflow."
' "$REVIEW_FILE")

if [[ "$FINDING_COUNT" -eq 0 ]]; then
  gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}/reviews" \
    -f body="$BODY" \
    -f event="COMMENT"
else
  # Build payload with inline comments
  PAYLOAD=$(jq -n \
    --arg body "$BODY" \
    --slurpfile review "$REVIEW_FILE" \
    '{
      body: $body,
      event: "COMMENT",
      comments: [
        $review[0].comments[] |
        {
          path: .path,
          line: .line,
          side: "RIGHT",
          body: ("**[" + (.severity // "low") + "]** " + .body + " _(confidence: " + ((.confidence // 0) | tostring) + ")_")
        }
      ]
    }')

  echo "$PAYLOAD" | gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}/reviews" --input - 2>/tmp/kiro-post-err && {
    echo "Review posted successfully (${FINDING_COUNT} inline comments)"
  } || {
    echo "::warning::Inline comments failed ($(cat /tmp/kiro-post-err)). Posting as body-only review."
    # Build fallback body with findings listed as text
    FALLBACK_BODY=$(jq -r --arg body "$BODY" '
      $body + "\n\n### Findings\n" +
      ([.comments[] | "**\(.path)** — **[" + (.severity // "low") + "]** " + .body + " _(confidence: " + ((.confidence // 0) | tostring) + ")_"] | join("\n\n"))
    ' "$REVIEW_FILE")
    gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}/reviews" \
      -f body="$FALLBACK_BODY" \
      -f event="COMMENT"
    echo "Review posted as body-only fallback (${FINDING_COUNT} findings)"
  }
fi
