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

Tell Utensil what produced the code being scanned. The most common case is an AI-assisted PR: set the `ai-*` typed inputs and the action assembles the right payload.

```yaml
      - uses: Stencia/utensil-ci-action@main
        with:
          license-token: ${{ secrets.UTENSIL_LICENSE_TOKEN }}
          ai-provider: Anthropic
          ai-tool: Claude Code
          ai-model: claude-sonnet-4-5
          ai-used-agent: 'true'
```

Optional inputs: `ai-feature`, `ai-mode`, `ai-agent-session-id`. `ai-used-agent` defaults to `false`. When any `ai-*` input is set, the action emits a single workflow-instrumentation entry with hardcoded structural fields and the typed metadata you provided. `authorship` is set to `vibeCoded` when `ai-used-agent` is `true` (agent-mode AI work) and to `human` otherwise (AI-assisted, but the commits remain human-authored; the `tool` / `provider` / `model` fields still record the assistance).

When the CLI runs inside a GitHub Actions runner, it auto-populates `repo`, `ref`, `sha`, `runId`, `trigger`, and `pullRequestNumber` from the standard `GITHUB_*` environment variables. On `pull_request` events, `ref` and `sha` come from `pull_request.head` rather than the synthetic merge ref. Autofill requires a Utensil CLI build that includes [wbraynen/Utensil#93](https://github.com/wbraynen/Utensil/pull/93) (merged 2026-04-13, lands in the first release after `v0.25.0-alpha`). Older CLIs leave the runner-context fields unset; the report stays valid either way.

### Escape hatch: raw JSON

For multiple entries per scan, custom structural fields, or a non-AI producer, pass `authorship-provenance-json` directly. When set, this takes precedence over the `ai-*` inputs.

```yaml
      - uses: Stencia/utensil-ci-action@main
        with:
          license-token: ${{ secrets.UTENSIL_LICENSE_TOKEN }}
          authorship-provenance-json: >-
            [{"authorship":"human","sourceType":"workflowInstrumentation","evidenceType":"workflowAttributionSignal","attributionScope":"platform","evidenceStrength":"weak","provider":"Anthropic","tool":"Claude Code","model":"claude-sonnet-4-5","usedAgent":true}]
```

In either form the action forwards the resolved payload to the CLI via `UTENSIL_EXTERNAL_AUTHORSHIP_PROVENANCE_JSON`.
