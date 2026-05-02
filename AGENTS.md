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

## Epic Continuity

- When the user asks "what's next" or says "next", first check whether there is an already-started epic, umbrella issue, or user-identified workstream that is still incomplete.
- Prefer finishing that in-flight epic before suggesting a new implementation track, even if some child PRs or child issues were merged.
- Do not treat tracker cleanup or recently closed child issues as sufficient proof that the higher-level epic is done. Reconcile the live issue state, recent merged work, and any explicit user callouts about missing scope before moving on.
- If an epic appears complete in GitHub but the user identifies a concrete remaining gap, treat the epic as still in flight until that gap is either implemented, explicitly deferred, or the tracker is corrected.
- Only suggest a brand-new track when the active epic is actually complete, explicitly parked by the user, or blocked hard enough that the user asks to switch.

## Issue Consolidation

- Before opening a new follow-up issue, check whether an existing open epic, parent issue, or prior follow-up already covers the remaining work closely enough to absorb it.
- Prefer consolidating residual work into one tracked follow-up issue under the existing epic or parent issue instead of creating multiple new issues from each recently closed child issue or PR.
- Do not create multiple new follow-up issues from a single closed issue or PR unless the user explicitly asks for that split or the work truly needs distinct ownership or execution tracks.
- Minor review findings, polish items, and residual hardening work should usually be recorded in an existing follow-up issue rather than spun out into separate new tickets.
- If a minor point does not deserve code work or a new ticket, record that triage explicitly in the relevant issue or PR context so it is consciously dismissed rather than forgotten.

## Upload vs Publish Paths

- Treat "upload" as ambiguous until the target surface is clear. There are two different paths:
  - **Workspace/customer dashboard upload:** The `Utensil` CLI `upload` command, the CI action `upload` step, and the hosted scan service all go through the customer ingest/grant flow (`/api/upload-grant` and `/api/ingest`). This path is only for repositories connected to a workspace the license holder belongs to.
  - **Public repo library / benchmark publish:** Open-source repos that should appear alongside Signal and the benchmark corpus do **not** use the workspace upload-grant path. They are scanned locally, ingested through `utensil-benchmark`, and then surfaced through the benchmark/web data path.
- Do not treat a workspace grant failure for an open-source repo as a product blocker if the actual goal is to add that repo to the public library.
- Before attempting any public-library publish for a new repo, first compare the current CLI report with a direct inspection of the repo itself.
- That comparison should happen before any ingest/publish step, and it should be done in parallel when practical:
  - run the current CLI against the repo
  - inspect the repo directly (dependency manifests, package stanzas, local packages, obvious scope/coverage expectations)
  - compare the two results and only then decide whether the repo is ready for benchmark/public-library ingestion

## PR Cleanup

- When the user says a pull request was merged, treat that as authorization to clean up that PR's local artifacts unless they say otherwise.
- "Clean up" means:
  - remove PR-specific review or implementation worktrees for that merged PR
  - delete the corresponding local git branches after the worktrees are removed
  - delete the remote head branch too when it still exists and clearly belongs to the merged PR
- Before deleting anything, verify which worktree and branch map to the merged PR so unrelated branches are not removed by mistake.

## PR Feedback

- When the user says to "address PR feedback on PR", treat that as authorization to do the full review-follow-up loop unless they say otherwise.
- Before addressing any review feedback on a PR, check whether the PR branch is conflicting with its base branch.
- If the PR is conflicting, resolve the merge/rebase conflict first, then continue with review follow-up work on the rebased branch state.
- That loop includes:
  - fetch unresolved review threads and implement the actionable fixes
  - run the relevant verification, commit, and push the PR branch
  - resolve any GitHub review thread whose requested change is now fully addressed by the pushed branch head
- Do not leave addressed threads unresolved just because a generic GitHub skill says thread resolution requires a separate explicit ask. This repo-local rule overrides that default.
- Do not resolve threads that are only partially addressed, ambiguous, or still need a substantive reply. Summarize those cases instead.

## CI Failure Reproduction

- When a GitHub Actions failure is specific to the Linux CLI workflow, reproduce and verify it in a Linux environment first.
- Do not treat macOS `swift test`, Xcode builds, or other host-platform checks as sufficient evidence that a Linux CLI failure is fixed.
- Prefer matching the failing workflow as closely as practical, including the container image, package-install step, and test/build command from the workflow file.
