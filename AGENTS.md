# Utensil CI Action

## Worktree Requirement

- Always work from a git worktree on a branch that is not `main`.
- Never make changes directly in the primary checkout.
- Before editing files or running repo-affecting git commands, verify the current checkout with `git branch --show-current` and confirm you are inside the intended worktree.

## Sibling Repo Discovery

- When a task refers to "all Utensil repos", use `/Users/will/code/utensil-all` as the source of truth.
- That directory is a local symlink inventory for the active Utensil repos. Enumerate it first instead of inferring repo scope from the current checkout.
- Current entries include:
  - `Utensil`
  - `utensil-benchmark`
  - `utensil-ci-action`
  - `utensil-cli-and-desktop`
  - `utensil-scan-service`
  - `utensil-vscode`
  - `utensil-web`
- After resolving the local repo paths from `/Users/will/code/utensil-all`, read each repo's `origin` remote to map it to the corresponding GitHub repository before querying PRs or review feedback.
