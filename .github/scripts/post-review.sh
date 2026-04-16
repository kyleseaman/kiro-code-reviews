#!/usr/bin/env bash
set -euo pipefail

# Posts or updates a single Kiro code review comment on the PR.
# Uses a hidden marker to find and edit the existing comment on subsequent reviews.
# Expects: PR_NUMBER, GITHUB_REPOSITORY, GH_TOKEN (set by the workflow)

REVIEW_FILE="/tmp/kiro-review.json"
COMMENT_FILE="/tmp/kiro-comment.md"
PR="$PR_NUMBER"
MARKER="<!-- kiro-code-review -->"

# Find existing review comment
COMMENT_ID=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" --paginate -q \
  ".[] | select(.body | contains(\"${MARKER}\")) | .id" | head -1)

post_comment() {
  if [[ -n "${COMMENT_ID:-}" ]]; then
    echo "Updating existing review comment (${COMMENT_ID})"
    gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${COMMENT_ID}" \
      -X PATCH -F "body=@${COMMENT_FILE}"
  else
    echo "Creating new review comment"
    gh pr comment "$PR" --body-file "$COMMENT_FILE"
  fi
}

# If no findings file, post a clean summary
if [[ ! -f "$REVIEW_FILE" ]]; then
  echo "No review file found — posting clean summary"
  printf '%s\n%s' "$MARKER" "✅ **Kiro Code Review** — No issues found." > "$COMMENT_FILE"
  post_comment
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
jq -r --arg marker "$MARKER" '
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

  $marker + "\n" +
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

post_comment

echo "Review posted successfully (${FINDING_COUNT} findings)"
