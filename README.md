# 🔍 Kiro Code Review Action

[![Kiro Code Review](https://img.shields.io/badge/Kiro_CLI-Code_Review-6C47FF?style=flat-square)](https://kiro.dev/docs/cli/headless/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

Automated PR code reviews powered by [Kiro CLI](https://kiro.dev/cli/) in headless mode. A custom AI agent analyzes your pull request diff for security vulnerabilities and code quality issues, then posts inline review comments directly on the PR.

---

## How It Works

```mermaid
flowchart LR
    A[PR opened/updated] --> B{Already reviewed\nthis SHA?}
    B -- Yes --> C[Skip]
    B -- No --> D[Install Kiro CLI]
    D --> E[Generate diff]
    E --> E2[Fetch linked issue context]
    E2 --> F[Coordinator agent]
    F --> G[🔴 Security subagent]
    F --> H[🔵 Quality subagent]
    F --> F2[🟣 Design review]
    G --> I[Merge findings]
    H --> I
    F2 --> I
    I --> J[Post inline comments + summary]
    J --> K[Post SHA-scoped marker]
```

1. A pull request is opened or updated
2. The workflow checks for a SHA-scoped marker comment — if found for the current HEAD, the review is skipped. New pushes get a fresh review.
3. Kiro CLI is installed and the PR diff is generated via `gh pr diff`
4. Linked issue context is fetched from the PR body (parses `Closes #N`, `Fixes #N`, etc.)
5. The `code-reviewer` coordinator agent reads the issue context, then spawns two subagents **in parallel**:
   - `code-security` — focused on security vulnerabilities, with codebase awareness for sibling files
   - `code-quality` — focused on bugs, error handling, code quality, and test coverage gaps
6. The coordinator performs its own **design review** — evaluating whether the PR fully addresses the linked issue, uses the right abstraction layer, and doesn't miss sibling components
7. All findings are merged, deduplicated, and posted as a single PR review with inline comments
8. A SHA-scoped marker comment is posted to prevent duplicate reviews for the same commit

---

## Features

| | |
|---|---|
| 🔴 **Security review** | Injection flaws, hardcoded secrets, insecure defaults, missing validation |
| 🟡 **Bug detection** | Null access, off-by-one errors, race conditions, resource leaks |
| 🟠 **Error handling** | Swallowed exceptions, missing error checks |
| 🔵 **Code quality** | Unnecessary complexity, dead code, poor naming |
| 🟣 **Design review** | Issue completeness, abstraction layer, sibling components, over-engineering |
| 🟤 **Test coverage** | Missing tests for new behavior, untested exports, stale test updates |
| 🧩 **Parallel subagents** | Security and quality reviews run simultaneously via Kiro subagents |
| 🔗 **Issue-aware** | Fetches linked issue context to evaluate whether the PR solves the stated problem |
| 🔍 **Codebase-aware** | Agents grep sibling files to catch patterns missed in the diff |
| 💬 **PR comment** | Findings posted as a single organized comment on the PR |
| 📝 **Summary** | Overall review summary posted as the review body |
| 🔄 **Per-commit review** | SHA-scoped markers — new pushes get fresh reviews |

---

## Quick Setup

### 1. Copy the files into your repo

```
your-repo/
├── .github/
│   ├── scripts/
│   │   └── post-review.sh
│   └── workflows/
│       └── kiro-code-review.yml
└── .kiro/
    └── agents/
        ├── code-reviewer.json          # Coordinator
        ├── code-security.json          # Security subagent
        ├── code-quality.json           # Quality subagent
        └── prompts/
            ├── code-reviewer.md
            ├── code-security.md
            └── code-quality.md
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

The action posts a PR comment that looks like this:

> 🤖 **Kiro Code Review**
>
> This PR introduces a new authentication endpoint. The implementation is mostly solid, but there are two security concerns around input validation and one potential null pointer issue.
>
> ### src/auth/handler.ts
> - 🔴 User input is passed directly to the SQL query without parameterization. Use prepared statements to prevent SQL injection.
> - 🟡 `user.email` can be `null` when the OAuth provider doesn't return an email. Add a null check before accessing `.toLowerCase()`.
>
> ### src/components/dropdown.tsx
> - 🟣 The linked issue asks for a central fix across all dropdown components, but this PR only modifies `DropdownItem`. The `Listbox` component has the same wrapping issue — consider addressing both.
> - 🟤 This PR adds a new exported `wrapBareTextChildren` function but includes no tests for it.
>
> ---
> *Found 4 finding(s). Powered by [Kiro CLI](https://kiro.dev/docs/cli/headless/).*

---

## Customization

### Changing what the agents review

Each subagent has its own prompt file:

- `.kiro/agents/prompts/code-security.md` — security focus areas and rules
- `.kiro/agents/prompts/code-quality.md` — bugs, error handling, and quality rules

Edit these to adjust review categories, severity levels, exclusions, or tone.

### Adding a new subagent

1. Create a new agent config (e.g., `.kiro/agents/code-performance.json`)
2. Create its prompt (e.g., `.kiro/agents/prompts/code-performance.md`)
3. Update the coordinator prompt in `code-reviewer.md` to spawn the new subagent

### Changing the model

Edit the `model` field in any agent's `.json` config:

```json
{
  "model": "claude-sonnet-4"
}
```

### Changing when it runs

Edit `.github/workflows/kiro-code-review.yml`:

```yaml
on:
  pull_request:
    types: [opened, synchronize]
    paths-ignore:
      - '**.md'
      - 'docs/**'
```

### Re-running a review

Push a new commit — the review is SHA-scoped, so each new push gets a fresh review automatically. To force a re-review of the same commit, delete its `<!-- kiro-review-{SHA} -->` marker comment from the PR and re-run the workflow.

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│  GitHub Actions Workflow                          │
│                                                   │
│  1. Check SHA marker → 2. Install CLI → 3. Diff  │
│  4. Fetch linked issue context                    │
│                                                   │
│  5. kiro-cli (coordinator agent)                  │
│     ├── reads issue context                       │
│     ├── spawns code-security (parallel)           │
│     ├── spawns code-quality  (parallel)           │
│     ├── performs design review                    │
│     └── merges → /tmp/kiro-review.json            │
│                                                   │
│  6. post-review.sh → gh pr comment               │
│  7. Post SHA-scoped marker comment                │
└──────────────────────────────────────────────────┘
```

The coordinator agent reads the linked issue context first, then delegates line-level analysis to specialized subagents that run in parallel with codebase awareness. Each subagent writes findings to a separate JSON file. The coordinator performs its own design review, reads all findings, deduplicates, and writes a merged result that the posting script submits as a single PR review.

---

## Project Structure

```
.github/
├── scripts/
│   └── post-review.sh              # Reads findings JSON, posts PR comment via gh
└── workflows/
    └── kiro-code-review.yml        # GitHub Actions workflow

.kiro/
└── agents/
    ├── code-reviewer.json           # Coordinator agent config
    ├── code-security.json           # Security subagent config
    ├── code-quality.json            # Quality subagent config
    └── prompts/
        ├── code-reviewer.md         # Coordinator prompt (spawn + merge)
        ├── code-security.md         # Security review prompt
        └── code-quality.md          # Quality review prompt
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Workflow doesn't trigger | Ensure the workflow file is on the default branch |
| "API key" errors | Verify `KIRO_API_KEY` is set in repo secrets |
| No review posted | Check the workflow logs — the agent may not have found issues |
| Review posted on every push | The SHA-scoped marker check may have failed — look for `<!-- kiro-review-{SHA} -->` in PR comments |
| No issue context | Ensure the PR body contains `Closes #N`, `Fixes #N`, or `Resolves #N` linking to an issue |

---

## Requirements

- [Kiro CLI](https://kiro.dev/cli/) (installed automatically by the workflow)
- Kiro Pro, Pro+, or Power subscription (for API key access)
- GitHub repository with Actions enabled

---

## License

[MIT](LICENSE)
