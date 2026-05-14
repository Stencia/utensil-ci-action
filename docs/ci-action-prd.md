# Utensil CI Action PRD

**Status:** PRD backfill
**Surface owner:** `Stencia/utensil-ci-action`

## Source of Truth

This repo owns the self-hosted GitHub Action surface for Utensil scans. The product-wide PR review model is specified in [`wbraynen/Utensil/docs/features/diff-scoped-pr-review.md`](https://github.com/wbraynen/Utensil/blob/main/docs/features/diff-scoped-pr-review.md).

This document covers the Action contract: workflow inputs, scan setup, upload behavior, PR comment handoff, and how the Action maps GitHub Actions context into the CLI.

## Purpose

The Action lets a repository run the Utensil CLI inside its own GitHub Actions runner. It supports two user-facing modes:

1. **PR review:** run on `pull_request`, scan the PR head, default to changed files, upload the report, and create/update a concise PR comment when there is something to report.
2. **Full scan:** run on `schedule`, `workflow_dispatch`, or branch workflows, scan the requested path or full repo, and optionally upload the report to the Utensil dashboard.

The Action is intentionally distinct from the hosted GitHub App runner in `utensil-scan-service`. Installing the App does not install this Action, and adding this Action does not use Utensil-hosted compute.

## Goals

- Provide a copy-pasteable CI entry point for Utensil.
- Keep scan execution inside the customer's runner.
- Make dashboard upload optional and non-fatal by default.
- Preserve PR review relevance by defaulting PR scans to changed files.
- Carry workflow authorship and scan target metadata into the CLI report.
- Improve code composition accuracy by installing dependencies when appropriate.

## Non-Goals

- Do not replace the hosted GitHub App runner.
- Do not make Utensil-side branch protection decisions. `fail-on` exits are local workflow policy.
- Do not store customer code in this Action repo.
- Do not infer product policy beyond what the CLI and canonical PR review spec define.

## User Jobs

1. Add Utensil scanning to a GitHub repository with one workflow step.
2. Upload scan results to Utensil when a valid license token is configured.
3. See relevant PR findings without historical repo debt flooding the comment.
4. Understand whether a CI failure came from findings, token setup, CLI startup, or upload trouble.
5. Attribute a scan to AI-assisted workflow context when the workflow has that data.

## Scan Contract

The Action assembles CLI arguments from typed inputs:

- `path` selects the repo or subdirectory to scan.
- `full` controls full-repo CLI mode.
- `fail-on` passes through to the CLI and converts matching findings into an Action failure.
- `debian-suite`, `debian-arch`, `native-resolvers`, and hosted scan-config values alter scanner scope and must be reflected in uploaded metadata.
- `args` remains an escape hatch and should not silently override explicit typed inputs except through normal CLI argument precedence.

On pull request events, `diff-only` defaults to changed-file scanning. The Action obtains changed files from the GitHub API using the provided `github-token`. If changed-file discovery fails, it warns and falls back to a full scan rather than silently skipping the scan.

## Dependency Installation

`install-dependencies` defaults to `true` because code composition analysis is materially better when package code is present on disk. The install step:

- walks upward from `path` to the workflow workspace to find a package manager lockfile
- supports npm, Yarn, and pnpm conventions
- uses script-disabled install commands where possible
- skips when `node_modules` already exists

Users can set `install-dependencies: "false"` when their workflow already installed dependencies or when they intentionally want manifest-only composition.

## Upload Contract

When `upload: "true"`, the Action POSTs the CLI JSON report to `upload-url` with:

- GitHub metadata: repo, ref, sha, run ID, trigger, and source
- scan-config metadata: config fetch status and scan target source
- report payload from the CLI

Upload failure is non-fatal. The workflow emits a warning because dashboard ingestion should not block a repository's CI unless the customer explicitly adds their own policy around it.

## PR Comment Contract

The Action owns the self-hosted Action PR comment, not the hosted GitHub App comment.

Requirements:

- use a stable hidden marker so repeated runs update the existing comment
- skip creating a comment when the scan has nothing to report
- delete a stale prior comment when a later run is clean
- render finding labels in human-readable form
- keep upload response handling separate from comment rendering failures

The Action does not perform server-side semantic AI evaluation itself. It posts the information available through the report and upload response.

## Check-Run Contract

The Action may create a check run when `github-token` has `checks: write`. Failure to create the check run must warn rather than masking the scan result. Repositories that want check-run gating must configure GitHub branch protection themselves or use `fail-on`.

## Authorship Provenance

Two input styles are supported:

- typed `ai-*` inputs for the common "AI-assisted workflow" case
- `authorship-provenance-json` as an escape hatch for advanced callers

Raw JSON wins over typed inputs. The resolved payload is passed to the CLI through `UTENSIL_EXTERNAL_AUTHORSHIP_PROVENANCE_JSON`; the CLI owns final schema validation.

## Hosted Scan Config

`fetch-scan-config` is best-effort. When enabled, the Action asks Utensil for tenant-owned scan target settings before scanning. Success or failure is reported through Action outputs and upload metadata. A failed config fetch does not skip the scan; the local workflow inputs remain authoritative.

## PRD Maintenance

Future behavior-changing PRs in this repo should update this file or explicitly cite the canonical `Utensil` PRD that already covers the behavior.

