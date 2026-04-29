def markdown_table_cell:
  tostring
  | gsub("[\\r\\n\\t]+"; " ");

def inferred_rule_label:
  (
    [.evidence[]?
      | select(.type == "inference" and (.reason // "" | startswith("Severity: ")))
      | .reason
    ][0] // ""
  )
  | sub("^Severity: [^.]+\\.\\s*"; "")
  | if length == 0
    then ""
    else capture("^(?<title>.*?)(?:\\.\\s+(?=[A-Z])|\\.$|$)").title
    end
  | sub("^\\s+"; "")
  | sub("\\s+$"; "");

# Prefer producer-supplied user-facing labels when present; fall back to the
# inferred severity title and finally the stable internal key. As of 2026-04,
# utensil-scan-service emits `displayName` for PII-style findings and `title`
# for the main security-rule families; `ruleLabel` remains a compatibility slot
# for any producer that emits it.
def rule_label:
  .displayName
  // .title
  // .ruleLabel
  // (inferred_rule_label | select(length > 0))
  // .key;

.findings[]?
| select(.aiVerdict == "real_risk" or .aiVerdict == "context_dependent")
| [
    (rule_label | markdown_table_cell),
    ((.filePath // "") | markdown_table_cell),
    ((.severity // "") | markdown_table_cell),
    ((if .aiVerdict == "real_risk" then "Risk" elif .aiVerdict == "context_dependent" then "Review" else "" end) | markdown_table_cell)
  ]
| @tsv
