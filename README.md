# 🔍 Kiro Code Review Action

[![Kiro Code Review](https://img.shields.io/badge/Kiro_CLI-Code_Review-6C47FF?style=flat-square)](https://kiro.dev/docs/cli/headless/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

Automated PR code reviews powered by [Kiro CLI](https://kiro.dev/cli/) in headless mode. A coordinator agent spawns specialized review agents in parallel, filters findings by confidence score, and posts inline review comments directly on the PR.

---

## How It Works

```mermaid
flowchart LR
    A[PR opened or\nmarked ready] --> B[Install Kiro CLI]
    B --> C[Annotate diff with line numbers]
    C --> D[Gather repo guidelines]
    D --> E[Fetch linked issue context]
    E --> F[Coordinator agent — Opus 4.6]
    F --> G[Guidelines #1]
    F --> H[Guidelines #2]
    F --> I[Bug Detection]
    F --> J[Git History]
    G --> K[Filter: confidence ≥ 80]
    H --> K
    I --> K
    J --> K
    F --> K
    K --> L[Post PR review with inline comments]
```

1. A pull request is opened (or a draft PR is marked ready)
2. Kiro CLI is installed and the PR diff is annotated with absolute line numbers
3. Repo guidelines (AGENTS.md, CLAUDE.md, .kiro/) are gathered
4. Linked issue context is fetched from the PR body (parses `Closes #N`, `Fixes #N`, etc.)
5. The coordinator agent (Opus 4.6) spawns **4 subagents in parallel** (Sonnet 4.6):
   - **Guidelines #1 & #2** — redundant compliance checks against repo guidelines (findings confirmed by both get boosted confidence)
   - **Bug Detection** — scans for bugs, error handling issues, and test coverage gaps
   - **Git History** — analyzes blame/log for context (fragile code, reverted fixes, churn)
6. The coordinator performs its own **design review** — evaluating completeness, abstraction layer, and approach
7. All findings are filtered by confidence (threshold: 80), deduplicated, and assigned severity
8. Results are posted as a PR review with inline comments on specific diff lines

---

## Features

| | |
|---|---|
| **4-agent architecture** | Guidelines compliance (2x), bug detection, git history analysis — all in parallel |
| **Confidence scoring** | Each finding scored 0-100; only ≥80 confidence findings are posted |
| **Design review** | Coordinator evaluates issue completeness, abstraction layer, sibling components |
| **Repo guidelines** | Checks changes against AGENTS.md, CLAUDE.md, and .kiro/ conventions |
| **Git history context** | Uses blame/log to identify fragile code, reverted fixes, and churn patterns |
| **Severity tags** | Findings tagged `[high]`, `[medium]`, `[low]` for clear prioritization |
| **Inline comments** | Findings posted on exact diff lines with confidence scores |
| **Issue-aware** | Fetches linked issue context to evaluate whether the PR solves the stated problem |
| **Verdict** | Clear merge recommendation: merge, merge with fixes, or needs rework |
| **One-time review** | Runs on PR open or draft ready; re-run manually via workflow_dispatch |

---

## Quick Setup

### 1. Copy the files into your repo

```
your-repo/
├── .github/
│   ├── scripts/
│   │   ├── annotate-diff.sh          # Adds line numbers to diff
│   │   └── post-review.sh            # Posts review via GitHub API
│   └── workflows/
│       └── kiro-code-review.yml
└── .kiro/
    └── agents/
        ├── code-reviewer.json          # Coordinator (Opus 4.6)
        ├── code-bugs.json              # Bug detection (Sonnet 4.6)
        ├── code-guidelines.json        # Guidelines compliance (Sonnet 4.6)
        ├── code-history.json           # Git history analysis (Sonnet 4.6)
        └── prompts/
            ├── code-reviewer.md
            ├── code-bugs.md
            ├── code-guidelines.md
            └── code-history.md
```

### 2. Add your Kiro API key

Go to **Settings → Secrets and variables → Actions** in your GitHub repo and add:

| Secret | Value |
|--------|-------|
| `KIRO_API_KEY` | Your Kiro API key ([generate one here](https://kiro.dev/docs/cli/authentication#authenticate-with-an-api-key-headless-mode)) |

> [!NOTE]
> API keys require a **Kiro Pro, Pro+, or Power** subscription.

### 3. Open a pull request

That's it. The workflow triggers automatically on new PRs and posts a review.

---

## Example Output

The action posts a PR review with inline comments:

**Review body** (summary + strengths + verdict):
> 🤖 **Kiro Code Review**
>
> This PR adds user authentication. The implementation is solid with good test coverage, but there's a null pointer issue and a missing input validation check.
>
> ### Strengths
> - Clean separation of auth logic into dedicated handler (src/auth/handler.ts)
> - Comprehensive test coverage for the happy path
>
> **Verdict: Merge with fixes** — Fix the null check and input validation before merge.
>
> ---
> *Found 2 finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).* · To re-run, go to Actions → Kiro Code Review → Run workflow.

**Inline comments** (on specific diff lines):
> **[high]** `user.email` can be `null` when the OAuth provider doesn't return an email. Calling `.toLowerCase()` will throw a TypeError at runtime. _(confidence: 92)_

> **[medium]** [design] The linked issue asks for auth across all routes, but this PR only adds it to `/api/users`. The `/api/admin` routes are unprotected. _(confidence: 88)_

---

## Customization

### Changing what the agents review

Each agent has its own prompt file:

- `.kiro/agents/prompts/code-bugs.md` — bug detection rules and focus areas
- `.kiro/agents/prompts/code-guidelines.md` — guidelines compliance rules
- `.kiro/agents/prompts/code-history.md` — git history analysis rules
- `.kiro/agents/prompts/code-reviewer.md` — coordinator prompt (spawning, filtering, design review)

### Adjusting the confidence threshold

The default threshold is 80. To change it, edit `code-reviewer.md`:

```
6. **Filter by confidence**: Drop any finding with confidence below 80.
```

### Changing the models

Edit the `model` field in any agent's `.json` config:

```json
{
  "model": "claude-sonnet-4.6"
}
```

The coordinator uses `claude-opus-4.6` by default; subagents use `claude-sonnet-4.6`.

### When the review runs

By default, the review runs **once when a PR is opened**. Subsequent pushes don't trigger a re-review — you re-run manually when you're ready.

To change this behavior, edit the `types` array in `.github/workflows/kiro-code-review.yml`:

```yaml
# Default: review on open or when draft is marked ready (manual re-run for subsequent pushes)
on:
  pull_request:
    types: [opened, ready_for_review]

# Review on every push (more thorough, higher cost)
on:
  pull_request:
    types: [opened, ready_for_review, synchronize]
```

| Mode | Trigger | Cost | Best for |
|------|---------|------|----------|
| `[opened, ready_for_review]` (default) | First commit / draft ready | Low — one review per PR | Teams that iterate quickly and re-run manually |
| `+ synchronize` | Every push | Higher — review per push | Teams that want continuous automated feedback |

Both modes support manual re-runs via workflow_dispatch.

### Re-running a review

To manually re-run a review on any PR:

1. Go to **Actions** → **Kiro Code Review** → **Run workflow**
2. Enter the PR number and click **Run workflow**

Or from the CLI:
```bash
gh workflow run kiro-code-review.yml -f pr_number=<PR_NUMBER>
```

### Adding an MCP server for semantic code search

[Augment](https://www.augmentcode.com/) semantic code search is pre-configured but disabled by default. To enable it:

1. Add `AUGMENT_API_KEY` to your repo secrets (Settings → Secrets → Actions).
2. Add `AUGMENT_API_KEY: ${{ secrets.AUGMENT_API_KEY }}` to the workflow env block.
3. Set `"disabled": false` in the `auggie` MCP config in the agent JSON files.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  GitHub Actions Workflow                              │
│                                                       │
│  1. Install CLI → 2. Annotate diff → 3. Guidelines   │
│  4. Fetch linked issue context                        │
│                                                       │
│  5. kiro-cli (coordinator — Opus 4.6)                 │
│     ├── spawns code-guidelines #1 (Sonnet 4.6)       │
│     ├── spawns code-guidelines #2 (Sonnet 4.6)       │
│     ├── spawns code-bugs        (Sonnet 4.6)         │
│     ├── spawns code-history     (Sonnet 4.6)         │
│     ├── filters by confidence (≥ 80)                  │
│     ├── performs design review                        │
│     └── merges → /tmp/kiro-review.json                │
│                                                       │
│  6. post-review.sh → GitHub reviews API               │
└──────────────────────────────────────────────────────┘
```

The coordinator reads issue context and repo guidelines, then delegates analysis to 4 specialized subagents running in parallel. Each subagent scores findings by confidence (0-100). The coordinator filters out anything below 80, boosts confidence when both guidelines agents agree, performs its own design review, and writes a merged result. The posting script submits it as a PR review with inline comments.

---

## Project Structure

```
.github/
├── scripts/
│   ├── annotate-diff.sh             # Adds [N] line annotations to diff
│   └── post-review.sh              # Posts review via GitHub reviews API
└── workflows/
    └── kiro-code-review.yml        # GitHub Actions workflow

.kiro/
└── agents/
    ├── code-reviewer.json           # Coordinator (Opus 4.6)
    ├── code-bugs.json               # Bug detection (Sonnet 4.6)
    ├── code-guidelines.json         # Guidelines compliance (Sonnet 4.6)
    ├── code-history.json            # Git history analysis (Sonnet 4.6)
    └── prompts/
        ├── code-reviewer.md         # Coordinator prompt
        ├── code-bugs.md             # Bug detection prompt
        ├── code-guidelines.md       # Guidelines compliance prompt
        └── code-history.md          # Git history prompt
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Workflow doesn't trigger | Ensure the workflow file is on the default branch |
| "API key" errors | Verify `KIRO_API_KEY` is set in repo secrets |
| No review posted | Check the workflow logs — the agent may not have found issues above the confidence threshold |
| No issue context | Ensure the PR body contains `Closes #N`, `Fixes #N`, or `Resolves #N` linking to an issue |
| No guidelines findings | Add an AGENTS.md, CLAUDE.md, or .kiro/ guidelines to your repo |
| Want to re-run | Go to Actions → Kiro Code Review → Run workflow → enter PR number |

---

## Requirements

- [Kiro CLI](https://kiro.dev/cli/) (installed automatically by the workflow)
- Kiro Pro, Pro+, or Power subscription (for API key access)
- GitHub repository with Actions enabled

---

## License

[MIT](LICENSE)
