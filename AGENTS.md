# Utensil CI Action

## Worktree Requirement

- Always work from a git worktree on a branch that is not `main`.
- Never make changes directly in the primary checkout, even if it is clean.
- The isolation unit is a concurrent workstream or PR branch, not an individual commit. If multiple changes belong in the same branch/PR, keep them in the same dedicated worktree.
- Create a new worktree when starting a separate branch/PR, when another agent may work in parallel, or when you need isolation from unrelated in-progress changes.
- Before editing files or running repo-affecting git commands, run `git worktree list --porcelain` and `git branch --show-current` and confirm you are inside the intended worktree rather than the primary checkout.
- Treat the primary checkout as read-only for development work.
- After a PR is merged, delete its worktree when no further work remains on that branch.

## Sibling Repo Discovery

- When a task refers to "all Utensil repos", use the directory named by `UTENSIL_ALL_REPOS` as the source of truth. If unset, use a local symlink inventory such as `~/code/utensil-all`.
- That directory is a local symlink inventory for the active Utensil repos. Enumerate it first instead of inferring repo scope from the current checkout.
- Current entries include:
  - `Utensil`
  - `utensil-benchmark`
  - `utensil-ci-action`
  - `utensil-cli-and-desktop`
  - `utensil-scan-service`
  - `utensil-vscode`
  - `utensil-web`
- After resolving the local repo paths from the symlink inventory, read each repo's `origin` remote to map it to the corresponding GitHub repository before querying PRs or review feedback.
