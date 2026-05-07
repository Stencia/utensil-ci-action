# Utensil CI Action

## Worktree Requirement

- Always work from a git worktree on a branch that is not `main`.
- Never make changes directly in the primary checkout, even if it is clean.
- The isolation unit is a concurrent workstream or PR branch, not an individual commit. If multiple changes belong in the same branch/PR, keep them in the same dedicated worktree.
- Create a new worktree when starting a separate branch/PR, when another agent may work in parallel, or when you need isolation from unrelated in-progress changes.
- Before cutting a new worktree or branch from `main`, sync `main` from `origin` first so you do not branch from a stale local checkout.
- Before editing files or running repo-affecting git commands, run `git worktree list --porcelain` and `git branch --show-current` and confirm you are inside the intended worktree rather than the primary checkout.
- Treat the primary checkout as read-only for development work.
- After a PR is merged, delete its worktree when no further work remains on that branch.

## Issue Assignment

- Before starting work on any tracked GitHub issue, assign the issue to yourself.
- Verify the live GitHub issue state shows you as the assignee before implementation, PR creation, or review-loop work begins.
- Do not start work on an issue that is assigned to someone else unless the user explicitly directs that handoff or the assignment is changed first.
- When the user asks for multiple issues to be done sequentially, assign each issue before taking it so parallel agents do not collide on the same work.

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

## Issue Assignment

- Treat any pre-existing GitHub assignee on an issue as proof that another agent is already working that issue.
- Do not choose, start, or continue an assigned issue unless the user explicitly tells you to take over or collaborate on that specific assigned issue.
- When asked "what's next", exclude assigned issues from candidate next steps unless the user explicitly names one.
- If an issue is unassigned and you are about to start it, assign it to yourself first.
- Do not start implementation, branch work, or substantial issue-specific investigation until that self-assignment is in place.
- The agent that just assigned an unassigned issue to itself may continue that issue in the same workstream; the guardrail is against taking issues that were already assigned before you started.
- When working a sequence of issues, assign each issue at the moment you are about to start that issue, not retroactively after work has begun.
- Treat assignment state as a hard concurrency guardrail, not a soft planning hint.

## Upload vs Publish Paths

- Treat "upload" as ambiguous until the target surface is clear. There are two different paths:
  - **Workspace/customer dashboard upload:** The `Utensil` CLI `upload` command, the CI action `upload` step, and the hosted scan service all go through the customer ingest/grant flow (`/api/upload-grant` and `/api/ingest`). This path is only for repositories connected to a workspace the license holder belongs to.
  - **Public repo library / benchmark publish:** Open-source repos that should appear alongside Signal and the benchmark corpus do **not** use the workspace upload-grant path. They are scanned locally, ingested through `utensil-benchmark`, and then surfaced through the benchmark/web data path.
- Do not treat a workspace grant failure for an open-source repo as a product blocker if the actual goal is to add that repo to the public library.
- Before attempting any public-library publish for a new repo, first compare the current CLI report with a direct inspection of the repo itself.
- That comparison should happen before any ingest/publish step. Run these two in parallel when practical:
  - run the current CLI against the repo
  - inspect the repo directly (dependency manifests, package stanzas, local packages, obvious scope/coverage expectations)
- Then compare the two results and decide whether the repo is ready for benchmark/public-library ingestion.

## PR Cleanup

- When the user says a pull request was merged, treat that as authorization to clean up that PR's local artifacts unless they say otherwise.
- "Clean up" means:
  - remove PR-specific review or implementation worktrees for that merged PR
  - delete the corresponding local git branches after the worktrees are removed
  - delete the remote head branch when it still exists, the merge commit on the base contains its work, and there are no commits on the remote branch beyond what was merged
- Before deleting anything, verify which worktree and branch map to the merged PR so unrelated branches are not removed by mistake.

## PR Feedback

- When the user says to "address PR feedback on PR", treat that as authorization to do the full review-follow-up loop unless they say otherwise.
- Before addressing any review feedback on a PR, check whether the PR branch is conflicting with its base branch.
- If the PR is conflicting, resolve the merge/rebase conflict first, then continue with review follow-up work on the rebased branch state.
- That loop includes:
  - fetch unresolved review threads and implement the actionable fixes
  - run the relevant verification, commit, and push the PR branch
  - check `gh pr checks` after pushing; if any check fails, fix in the same worktree and re-push before reporting back
  - resolve any GitHub review thread whose requested change is now fully addressed by the pushed branch head
- Do not leave addressed threads unresolved just because a generic GitHub skill says thread resolution requires a separate explicit ask. This repo-local rule overrides that default.
- Do not resolve threads that are only partially addressed, ambiguous, or still need a substantive reply. Summarize those cases instead.

## PR Creation Default

- When the user says `go`, `implement`, `yes`, or otherwise authorizes tracked issue, epic, or planned work, treat that as authorization to carry the work through local verification, PR creation or update, and PR review convergence unless they explicitly say to stop before PR creation.
- Do not stop at "implementation is done locally" for tracked work when the expected outcome is a landed PR. After relevant verification succeeds, create or update the PR instead of waiting for a separate prompt to do so.
- Once the PR exists, continue the review-follow-up loop on the live PR head: gather review feedback, fix validated findings, rerun verification, push, and repeat until no actionable PR-attributable findings remain or the user redirects the work.

## CI Failure Reproduction

- When a GitHub Actions failure is specific to the Linux CLI workflow, reproduce and verify it in a Linux environment first.
- Do not treat macOS `swift test`, Xcode builds, or other host-platform checks as sufficient evidence that a Linux CLI failure is fixed.
- Prefer matching the failing workflow as closely as practical, including the container image, package-install step, and test/build command from the workflow file.
