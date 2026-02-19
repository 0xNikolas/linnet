# Development Workflow

## Planning & Execution

- **Always work using plans** — save to `agents/plans/`
- If requirements aren't clear, **ask questions first**
- Once the task is clear, **create a plan** and present it
- After user gives the go-ahead, **execute all tasks in the plan without further questions**

## Security

- **Never commit** private keys, API keys, secrets, mnemonics, or credentials
- **Never commit** absolute paths containing usernames — use `~` or relative paths
- **Verify `.gitignore`** covers `.env`, `.env.*`, and credential files before adding new ones
- **Scan staged files** for secrets and personal paths before committing (`git diff --cached`)
- **Use environment variables** for any deployment-sensitive values (RPC URLs, deployer keys, etc.)
- **Mark test keys as test-only** — use Foundry's default test accounts and annotate them clearly

## Committing & CI

- **Show changes before committing** — present a diff summary and wait for user approval before running `git commit`
- **Commit per scope**, not per sub-task — group related changes into logical commits
- **Conventional Commits** with semantic release: `type(scope): description`
  - Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`, `build`
  - Release impact: `feat` = minor, `fix`/`refactor`/`docs` = patch, `test`/`chore`/`ci`/`build` = no release
  - Breaking changes: add `BREAKING CHANGE` in commit body → major release
- **Run the full test suite** before committing
- After pushing, **wait for CI checks** and fix any failures
- Pre-commit hooks may auto-push, so `git push` might say "up to date"
  - Do NOT add `Co-Authored-By: Claude Opus x.x <noreply@anthropic.com>` to commit messages

## Completion

- A task is done only after the PR is merged and all CI checks pass
- **Never merge PRs** unless specifically asked to do so
- Ask for feedback after each task to improve workflow iteratively

## Communication Style

- When offering choices, **recommend the best option** with reasoning — don't just list options
- Keep status updates concise (summary tables, bullet points)

## Housekeeping

- Keep the local `agents/` folder updated with plans and relevant artifacts
- **Clean up plans** from `agents/plans/` once the task is done (PR merged, Linear task status set to "Done")
