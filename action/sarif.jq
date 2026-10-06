# Copyright 2026 Radoslaw Brus. SPDX-License-Identifier: Apache-2.0.
#
# sixi-scanner's JSON report -> SARIF 2.1.0, in the same shape the scanner's own `--format sarif`
# writes (internal/report/sarif.go). The action needs the JSON for what SARIF cannot carry -- which
# techniques got no answer -- so it scans once and renders the SARIF here instead of scanning twice.
def level: if . == "critical" or . == "high" then "error"
           elif . == "medium" or . == "low" then "warning" else "note" end;
def uri: "sixi-scanner://" + (.target | gsub("[^A-Za-z0-9._~-]"; "-"));
def clip($n): if length > $n then .[0:$n] + "…" else . end;
"https://github.com/rbrus/sixi-scanner" as $info
| (.findings // []) as $f
| uri as $u
| {
    "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
    version: "2.1.0",
    runs: [{
      tool: {driver: {
        name: .tool, informationUri: $info, version: .version,
        rules: ($f | unique_by(.technique_id) | map({
          id: .technique_id, name: .title,
          shortDescription: {text: .title},
          fullDescription: {text: .description},
          help: {text: (.remediation + (if (.rounds | length) > 1 then "\n\nReproduced in \(.rounds | length) scan rounds." else "" end))},
          helpUri: ($info + "#" + .technique_id),
          properties: {tags: (["security", "llm", "agentic-ai"] + (if .category then [.category] else [] end)), severity: .severity},
          defaultConfiguration: {level: (.severity | level)}
        }))
      }},
      results: ($f | map({
        ruleId: .technique_id, level: (.severity | level),
        message: {text: .evidence.reason},
        locations: [{physicalLocation: {artifactLocation: {uri: $u},
          region: {startLine: 1, snippet: {text: (.evidence.response | clip(400))}}}}],
        partialFingerprints: {"sixiScan/v1": .fingerprint}
      })),
      invocations: [{executionSuccessful: ($f | length == 0), exitCode: (if ($f | length) > 0 then 1 else 0 end)}]
    }]
  }
