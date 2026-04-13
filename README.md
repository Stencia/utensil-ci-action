# Utensil Scan Action

GitHub Action for running the Utensil CLI in CI, optionally uploading results to the Utensil dashboard, and posting PR findings metadata.

## Basic usage

```yaml
jobs:
  utensil:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      checks: write
    steps:
      - uses: actions/checkout@v4
      - uses: Stencia/utensil-ci-action@main
        with:
          license-token: ${{ secrets.UTENSIL_LICENSE_TOKEN }}
          upload: "true"
```

## Workflow authorship provenance

`authorship-provenance-json` lets a caller attach workflow or platform attribution metadata to the CLI report. Pass either a JSON array of entries or a wrapped object with an `entries` array. `provider`, `tool`, and `model` should describe whatever produced the code being scanned.

```yaml
      - uses: Stencia/utensil-ci-action@main
        with:
          license-token: ${{ secrets.UTENSIL_LICENSE_TOKEN }}
          authorship-provenance-json: >-
            [{"authorship":"human","sourceType":"workflowInstrumentation","evidenceType":"workflowAttributionSignal","attributionScope":"platform","evidenceStrength":"weak","provider":"Anthropic","tool":"Claude Code","model":"claude-sonnet-4-5","usedAgent":true}]
```

The action forwards this input to the CLI via `UTENSIL_EXTERNAL_AUTHORSHIP_PROVENANCE_JSON`.

When the CLI runs inside a GitHub Actions runner, it auto-populates `repo`, `ref`, `sha`, `runId`, `trigger`, and `pullRequestNumber` from the standard `GITHUB_*` environment variables, so they can be omitted from the payload. On `pull_request` events, `ref` and `sha` come from `pull_request.head` rather than the synthetic merge ref. Explicit payload fields always win over autofill, so callers that need a specific value can still set it.

Autofill requires a Utensil CLI build that includes [wbraynen/Utensil#93](https://github.com/wbraynen/Utensil/pull/93) (merged 2026-04-13, lands in the first release after `v0.25.0-alpha`). Older CLIs accept the same minimal payload but will leave the runner-context fields unset; the report stays valid either way.
