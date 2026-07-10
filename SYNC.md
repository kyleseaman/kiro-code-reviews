# Keeping the two companions in sync

This tool ships as two sibling repos that share ~90% of their content:

| Repo | Platform | Diff | Terminology |
|---|---|---|---|
| `kyleseaman/kiro-code-reviews` (this repo) | GitHub Actions + `gh` | `/tmp/pr.diff` | PR |
| `kyleseaman/kiro-gitlab-code-review` | GitLab CI + MR API | `/tmp/mr.diff` | MR |

They do not auto-sync. **Every fix is a two-repo change by default** — a fix
applied to one and not the other is a bug, not a difference. (This has already
happened once: three review fixes landed here and missed the GitLab repo for a
full cycle.)

## Checklist for any change

1. Does the change touch shared content (agent JSONs, prompts, annotate-diff,
   post-review logic, README concepts)? If yes → apply to BOTH repos in the
   same working session.
2. Adapt only terminology and platform APIs (PR/MR, `pr.diff`/`mr.diff`,
   `gh api` reviews vs GitLab discussions, Actions vars vs CI/CD variables).
3. Re-run each repo's checks: `jq empty` on agent JSONs, `bash -n` on scripts,
   YAML parse on the workflow/pipeline file.

## Intentional differences (do NOT sync these)

- **Augment Code (`auggie`) MCP** — present here (reviewer + bugs agents),
  deliberately absent from the GitLab repo.
- **Posting mechanics** — GitHub uses a single reviews-API call with a comments
  array (non-integer-line findings partitioned into the body up front); GitLab
  posts per-finding positioned discussions with per-finding fallback.
- **Gate plumbing** — `vars.KIRO_REVIEW_BLOCK` (Actions variable) here;
  `KIRO_REVIEW_BLOCK` CI/CD variable on GitLab.
- **Re-run affordance** — `workflow_dispatch` here; new pipeline run on GitLab.
