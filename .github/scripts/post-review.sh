#!/usr/bin/env bash
set -euo pipefail

# Posts kiro code review findings as a PR review via the GitHub API.
# Expects: GITHUB_REPOSITORY, PR_NUMBER, GH_TOKEN (set by the workflow)

REVIEW_FILE="/tmp/kiro-review.json"
OWNER_REPO="$GITHUB_REPOSITORY"
PR="$PR_NUMBER"

# If no findings file, post a clean review
if [[ ! -f "$REVIEW_FILE" ]]; then
  echo "No review file found — posting clean summary"
  gh api "repos/${OWNER_REPO}/pulls/${PR}/reviews" \
    -f body="✅ **Kiro Code Review** — No issues found." \
    -f event="COMMENT"
  exit 0
fi

# Validate JSON
if ! jq empty "$REVIEW_FILE" 2>/dev/null; then
  echo "::error::Invalid JSON in $REVIEW_FILE"
  exit 1
fi

COMMENT_COUNT=$(jq '.comments | length' "$REVIEW_FILE")
SUMMARY=$(jq -r '.summary // "No summary provided."' "$REVIEW_FILE")
BODY="🤖 **Kiro Code Review**

${SUMMARY}

---
*Found ${COMMENT_COUNT} finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).*"

if [[ "$COMMENT_COUNT" -eq 0 ]]; then
  gh api "repos/${OWNER_REPO}/pulls/${PR}/reviews" \
    -f body="$BODY" \
    -f event="COMMENT"
else
  # Build the payload with inline comments
  PAYLOAD=$(jq -n \
    --arg body "$BODY" \
    --slurpfile review "$REVIEW_FILE" \
    '{
      body: $body,
      event: "COMMENT",
      comments: [ $review[0].comments[] | {path, line, side, body} ]
    }')

  echo "$PAYLOAD" | gh api "repos/${OWNER_REPO}/pulls/${PR}/reviews" --input -
fi

echo "Review posted successfully (${COMMENT_COUNT} inline comments)"
