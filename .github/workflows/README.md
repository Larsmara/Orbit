# GitHub Actions workflows

## Description
CI/CD for the Orbit repo: lint gates on every push/PR, automatic minor-version tagging, packaged releases to CurseForge, and a label-driven Claude bot that fixes issues on the `ai-develop` branch.

## Purpose
Orbit has no automated test suite, so these lints are the only pre-merge gate; the tag/release chain makes every merge to `main` ship to CurseForge without manual steps.

## Implementation
The stable pipeline is lint → auto-tag → release:

| File | Trigger | Does |
|---|---|---|
| [`lint.yml`](lint.yml) | PR / push to `main` | four status checks: `check-localization.py`, `check-readmes.py`, `check-comments.py`, `check_mixin_freeze.py` |
| [`auto-tag.yml`](auto-tag.yml) | push to `main` (paths: `Orbit/**`, `.scripts/**`, `.pkgmeta`, `CHANGELOG.md`) | bumps MINOR, pushes `X.Y` tag using `ORBIT_PAT` |
| [`release.yml`](release.yml) | tag push `X.Y` / `X.Y.Z` (pattern also matches `X.Y-alpha.*`) | `update_changelog.py` (stable tags only) → BigWigs packager → CurseForge, alpha or release channel chosen by the tag suffix |
| [`alpha-release.yml`](alpha-release.yml) | manual (`workflow_dispatch`) | tags `ai-develop` HEAD as `X.<next-minor>-alpha.<timestamp>`, which then flows through `release.yml` |
| [`claude-issues.yml`](claude-issues.yml) | issue labeled `claude-approved` by the repo owner | syncs `ai-develop` ← `main`, runs `claude-code-action` to fix the issue, commits `fix(#N): …`, upserts the rolling PR `ai-develop → main`, removes the label; on failure comments the run URL and applies `claude-failed` |

Versioning is `MAJOR.MINOR`: major is manual (`git tag -a 1.0 -m "..." && git push origin 1.0`), minor auto-bumps on every qualifying push to `main`.

Repository secrets:

| Secret | Used by | Notes |
|---|---|---|
| `ORBIT_PAT` | `auto-tag.yml`, `alpha-release.yml`, `claude-issues.yml` (PR upsert) | personal access token — required because tags pushed with the default `GITHUB_TOKEN` do not trigger `release.yml` |
| `CURSE_API_KEY` | `release.yml` (exported as `CF_API_KEY`) | CurseForge upload auth |
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude-issues.yml` | generate via `claude setup-token`; consumes Pro/Max 5-hour quota — swap for an API key if it bottlenecks |

Claude resolver one-time setup: create labels `claude-approved` / `claude-failed`, create the `ai-develop` branch from `main`, add `CLAUDE_CODE_OAUTH_TOKEN`, install [github.com/apps/claude](https://github.com/apps/claude), and enable "allow GitHub Actions to create and approve pull requests" in repo settings.

## Gotchas
- Tag created but no release run → `ORBIT_PAT` expired. CurseForge upload fails → `CURSE_API_KEY` rotated. Claude run silently fails to start → label gate not satisfied (only the repo owner adding `claude-approved` counts) or the OAuth token expired.
- Alpha tags are filtered out when computing the next stable version, and `release.yml` skips the changelog build for them — the changelog tracks stable releases only.
- `alpha-release.yml` always tags `ai-develop` HEAD regardless of the branch it was dispatched from.
- Claude fixes are direct commits to `ai-develop`, not per-issue branches — revert with `git revert <sha>`. The `claude-bot` concurrency group serializes runs. Re-add `claude-approved` to retry a failed run.
- A merge conflict between `ai-develop` and `main` aborts the Claude run before Claude starts; resolve manually, then re-label.

## References
- Lint scripts: `.scripts/` at the repo root.
- [BigWigs packager](https://github.com/BigWigsMods/packager) — packaging + CurseForge upload; library externals come from `.pkgmeta`.
- [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action) — the issue-resolver action.
