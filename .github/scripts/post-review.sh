#!/usr/bin/env bash
set -euo pipefail

# Posts kiro code review findings as a PR comment via the GitHub API.
# Expects: PR_NUMBER, GH_TOKEN (set by the workflow)

REVIEW_FILE="/tmp/kiro-review.json"
PR="$PR_NUMBER"

# If no findings file, post a clean summary
if [[ ! -f "$REVIEW_FILE" ]]; then
  echo "No review file found — posting clean summary"
  gh pr comment "$PR" --body "✅ **Kiro Code Review** — No issues found."
  exit 0
fi

# Validate JSON
if ! jq empty "$REVIEW_FILE" 2>/dev/null; then
  echo "::error::Invalid JSON in $REVIEW_FILE"
  exit 1
fi

FINDING_COUNT=$(jq '.comments | length' "$REVIEW_FILE")
SUMMARY=$(jq -r '.summary // "No summary provided."' "$REVIEW_FILE")

# Build findings list grouped by file
FINDINGS=""
if [[ "$FINDING_COUNT" -gt 0 ]]; then
  FINDINGS=$(jq -r '.comments | group_by(.path)[] | "### \(.[0].path)\n" + (map("- \(.body)") | join("\n")) + "\n"' "$REVIEW_FILE")
fi

BODY="🤖 **Kiro Code Review**

${SUMMARY}

${FINDINGS}
---
*Found ${FINDING_COUNT} finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).*"

gh pr comment "$PR" --body "$BODY"

echo "Review posted successfully (${FINDING_COUNT} findings)"
