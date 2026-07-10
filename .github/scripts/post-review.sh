#!/usr/bin/env bash
# ABOUTME: Posts AI-generated code review findings as inline comments via GitHub API.
# ABOUTME: Handles summary formatting, verdict labeling, payload construction, and the merge gate.
set -euo pipefail

REVIEW_FILE="/tmp/kiro-review.json"
PR="${PR_NUMBER:-}"

# Fail early if the PR number is missing — otherwise API calls resolve to the
# list of all pull requests and behave unpredictably.
if [[ -z "$PR" ]]; then
  echo "::error::PR_NUMBER environment variable is missing or empty."
  exit 1
fi

# Merge-gate controls.
#   KIRO_REVIEW_BLOCK  — when truthy, a "needs rework" verdict fails this job so the PR
#                        check goes red (blocks merge when the check is required via
#                        branch protection). Default false → advisory only.
#   Per-PR override     — add the `skip-kiro-review` label to bypass the gate on one PR.
# The gate status is folded into the single review body (below), not posted as a
# separate comment, so re-runs don't clutter the PR conversation.
BYPASS_LABEL="skip-kiro-review"

is_truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Post a review (event=COMMENT) with the given body.
post_review() {
  gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}/reviews" \
    -f body="$1" \
    -f event="COMMENT"
}

# --- No findings file: post a clean review (no verdict → gate can't block) ------
if [[ ! -f "$REVIEW_FILE" ]]; then
  echo "No review file found — posting clean summary"
  post_review "✅ **Kiro Code Review** — No issues found."
  exit 0
fi

# --- Validate JSON -------------------------------------------------------------
if ! jq empty "$REVIEW_FILE" 2>/dev/null; then
  echo "::error::Invalid JSON in $REVIEW_FILE"
  echo "--- File contents ---"
  cat "$REVIEW_FILE"
  echo "--- End of file ---"
  exit 1
fi

FINDING_COUNT=$(jq '.comments // [] | length' "$REVIEW_FILE")
VERDICT=$(jq -r '.verdict // "" | ascii_downcase' "$REVIEW_FILE")

# --- Merge gate: decide state up front (fetch labels once) ---------------------
# BLOCKING=true → exit non-zero after posting. GATE_SUFFIX is appended to the
# single review body so status is conveyed without a separate comment.
BLOCKING=false
GATE_SUFFIX=""
if is_truthy "${KIRO_REVIEW_BLOCK:-false}" && [[ "$VERDICT" == "needs rework" ]]; then
  LABELS=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}" --jq '.labels[].name' 2>/dev/null || true)
  if printf '%s\n' "$LABELS" | grep -qx "$BYPASS_LABEL"; then
    GATE_SUFFIX=$'\n\n> ⚠️ **Merge gate bypassed** — verdict is `needs rework`, but the `'"$BYPASS_LABEL"$'` label is set, so this check will not fail.'
    echo "Verdict 'needs rework' bypassed by '${BYPASS_LABEL}' label. Not blocking."
  else
    BLOCKING=true
    GATE_SUFFIX=$'\n\n> 🚫 **Merge gate** — verdict is `needs rework`, so this check is failing to block the merge. Address the findings above and re-run, or add the `'"$BYPASS_LABEL"$'` label to override.'
  fi
fi

# --- Build review body (summary + strengths + verdict) -------------------------
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

# Fold the merge-gate status into the same review body.
BODY="${BODY}${GATE_SUFFIX}"

# --- Post the review (single post; inline comments when findings exist) --------
if [[ "$FINDING_COUNT" -eq 0 ]]; then
  post_review "$BODY"
else
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
    FALLBACK_BODY=$(jq -r --arg body "$BODY" '
      $body + "\n\n### Findings\n" +
      ([.comments // [] | .[] | "**\(.path)** — **[" + (.severity // "low") + "]** " + .body + " _(confidence: " + ((.confidence // 0) | tostring) + ")_"] | join("\n\n"))
    ' "$REVIEW_FILE")
    post_review "$FALLBACK_BODY" || echo "::error::Fallback review post also failed"
    echo "Review posted as body-only fallback (${FINDING_COUNT} findings)"
  }
fi

# --- Merge gate: exit code only (status already in the review body) ------------
if [[ "$BLOCKING" == "true" ]]; then
  echo "::error::Merge gate: verdict 'needs rework' with blocking enabled → failing check."
  exit 1
fi
exit 0
