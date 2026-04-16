#!/usr/bin/env bash
set -euo pipefail

# Posts a PR review with inline comments via the GitHub reviews API.
# Summary goes in the review body, findings become inline comments on specific lines.
# Expects: PR_NUMBER, GITHUB_REPOSITORY, GH_TOKEN (set by the workflow)

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

FINDING_COUNT=$(jq '.comments | length' "$REVIEW_FILE")

# Build review body (summary + strengths + verdict)
BODY=$(jq -r '
  def verdict_emoji:
    if .verdict == "merge" then "✅"
    elif .verdict == "merge with fixes" then "⚠️"
    elif .verdict == "needs rework" then "🛑"
    else "❓" end;

  "🤖 **Kiro Code Review**\n\n" +
  (.summary // "No summary provided.") + "\n\n" +
  (if .strengths and (.strengths | length) > 0
    then "### Strengths\n" + (.strengths | map("- \(.)") | join("\n")) + "\n\n"
    else "" end) +
  verdict_emoji + " **Verdict: " + (.verdict // "no verdict") + "**" +
  (if .verdict_reason and .verdict_reason != "" then " — " + .verdict_reason else "" end) +
  "\n\n---\n*Found \(.comments | length) finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).*"
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
          body: (
            (if .severity == "critical" then "**Critical** — "
             elif .severity == "important" then "**Important** — "
             else "" end) +
            .body
          )
        }
      ]
    }')

  echo "$PAYLOAD" | gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}/reviews" --input -
fi

echo "Review posted successfully (${FINDING_COUNT} inline comments)"
