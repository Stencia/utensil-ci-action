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

`authorship-provenance-json` lets a caller attach workflow or platform attribution metadata to the CLI report. Pass either a JSON array of entries or a wrapped object with an `entries` array.

```yaml
      - uses: Stencia/utensil-ci-action@main
        with:
          license-token: ${{ secrets.UTENSIL_LICENSE_TOKEN }}
          authorship-provenance-json: >-
            [{"authorship":"human","sourceType":"workflowInstrumentation","evidenceType":"workflowAttributionSignal","attributionScope":"platform","evidenceStrength":"weak","provider":"GitHub","tool":"Utensil Scan Service","trigger":"pull_request","runId":"${{ github.run_id }}"}]
```

The action forwards this input to the CLI via `UTENSIL_EXTERNAL_AUTHORSHIP_PROVENANCE_JSON`.
