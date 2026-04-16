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
VERDICT=$(jq -r '.verdict // "no verdict"' "$REVIEW_FILE")
VERDICT_REASON=$(jq -r '.verdict_reason // ""' "$REVIEW_FILE")

# Verdict emoji
case "$VERDICT" in
  "merge") VERDICT_EMOJI="✅" ;;
  "merge with fixes") VERDICT_EMOJI="🟡" ;;
  "needs rework") VERDICT_EMOJI="🔴" ;;
  *) VERDICT_EMOJI="❓" ;;
esac

# Build strengths section
STRENGTHS=$(jq -r 'if .strengths and (.strengths | length) > 0 then "### Strengths\n" + (.strengths | map("- \(.)") | join("\n")) + "\n" else "" end' "$REVIEW_FILE")

# Build findings grouped by severity
CRITICAL=$(jq -r '[.comments[] | select(.severity == "critical")] | if length > 0 then "### Critical (Must Fix)\n" + (group_by(.path)[] | "**\(.[0].path)**\n" + (map("- \(.body)") | join("\n"))) + "\n" else "" end' "$REVIEW_FILE")
IMPORTANT=$(jq -r '[.comments[] | select(.severity == "important")] | if length > 0 then "### Important (Should Fix)\n" + (group_by(.path)[] | "**\(.[0].path)**\n" + (map("- \(.body)") | join("\n"))) + "\n" else "" end' "$REVIEW_FILE")
MINOR=$(jq -r '[.comments[] | select(.severity == "minor")] | if length > 0 then "### Minor (Nice to Have)\n" + (group_by(.path)[] | "**\(.[0].path)**\n" + (map("- \(.body)") | join("\n"))) + "\n" else "" end' "$REVIEW_FILE")

# Build verdict section
VERDICT_SECTION="${VERDICT_EMOJI} **Verdict: ${VERDICT}**"
if [[ -n "$VERDICT_REASON" ]]; then
  VERDICT_SECTION="${VERDICT_SECTION} — ${VERDICT_REASON}"
fi

BODY="🤖 **Kiro Code Review**

${SUMMARY}

${STRENGTHS}
${CRITICAL}${IMPORTANT}${MINOR}
${VERDICT_SECTION}

---
*Found ${FINDING_COUNT} finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).*"

gh pr comment "$PR" --body "$BODY"

echo "Review posted successfully (${FINDING_COUNT} findings, verdict: ${VERDICT})"
