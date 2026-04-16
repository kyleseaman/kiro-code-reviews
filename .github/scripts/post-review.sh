#!/usr/bin/env bash
set -euo pipefail

# Posts kiro code review findings as a PR comment via the GitHub API.
# Expects: PR_NUMBER, GH_TOKEN (set by the workflow)

REVIEW_FILE="/tmp/kiro-review.json"
COMMENT_FILE="/tmp/kiro-comment.md"
PR="$PR_NUMBER"

# If no findings file, post a clean summary
if [[ ! -f "$REVIEW_FILE" ]]; then
  echo "No review file found — posting clean summary"
  echo "✅ **Kiro Code Review** — No issues found." > "$COMMENT_FILE"
  gh pr comment "$PR" --body-file "$COMMENT_FILE"
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

# Build the entire comment via jq to avoid shell expansion of user content
jq -r '
  def severity_section(sev; heading):
    [.comments[] | select(.severity == sev)]
    | if length > 0 then
        "### " + heading + "\n" +
        (group_by(.path)[] | "**\(.[0].path)**\n" + (map("- \(.body)") | join("\n"))) +
        "\n"
      else "" end;

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
  severity_section("critical"; "Critical (Must Fix)") +
  severity_section("important"; "Important (Should Fix)") +
  severity_section("minor"; "Minor (Nice to Have)") +
  "\n" + verdict_emoji + " **Verdict: " + (.verdict // "no verdict") + "**" +
  (if .verdict_reason and .verdict_reason != "" then " — " + .verdict_reason else "" end) +
  "\n\n---\n*Found \(.comments | length) finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).*"
' "$REVIEW_FILE" > "$COMMENT_FILE"

gh pr comment "$PR" --body-file "$COMMENT_FILE"

echo "Review posted successfully (${FINDING_COUNT} findings)"
