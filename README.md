# sixi-scanner — GitHub Action

Part of **Sixi**, a set of open projects for securing agentic AI.

Red-teams an LLM agent endpoint with the open-source [**sixi-scanner**](https://github.com/rbrus/sixi-scanner)
and files the findings as SARIF in the repository's Security tab.

The scanner is built from source on the runner and talks to your agent directly: no hosted service,
no account, no token, no telemetry. 21 publicly documented techniques, and every finding carries the
prompt and reply behind it.

```yaml
name: agent-security
on:
  schedule:
    - cron: "0 5 * * 1"        # Monday 05:00 UTC
  workflow_dispatch:

permissions:
  security-events: write       # the SARIF upload
  contents: read

jobs:
  sixi:
    runs-on: ubuntu-latest
    steps:
      - uses: rbrus/scan-action@v2
        id: sixi
        with:
          url: https://assistant.example.com/v1/chat/completions
          headers: |
            Authorization: Bearer ${{ secrets.ASSISTANT_TOKEN }}
          fail-on: high

      - uses: github/codeql-action/upload-sarif@v3
        if: always() && steps.sixi.outputs.sarif-path != ''
        with:
          sarif_file: ${{ steps.sixi.outputs.sarif-path }}
          category: sixi
```

`if: always()` matters: the upload must run when the scan step exits 1, which is the run that has
something to show.

## How it measures

On the [Agent Red-Team Benchmark](https://github.com/rbrus/agent-redteam-benchmark), against one
real Microsoft Foundry agent behind Azure's strictest content safety and scored by deterministic
oracles plus a tool-blind judge, sixi-scanner v0.5.1 was **1st of seven tools on precision (0.452)
and on recall (0.750)**, for $0.46. Its gap is breadth: a fixed set of 21 techniques is a floor, not
a state of the art. The benchmark is maintained by the scanner's author; the conflict of interest is
stated there, with every raw finding published.

## Exit codes

A job that treats every non-zero exit as "fix the agent" is wrong about two of them.

| Exit | Meaning | What to do |
|---|---|---|
| 0 | Scanned, nothing at or above `fail-on` | Nothing. A clean result means these probes found nothing; it is not an assurance |
| 1 | Findings at or above `fail-on` | Open the summary or the SARIF; each finding names the technique and the fix |
| 2 | Nothing was assessed: bad inputs, or no technique got an answer | Check the URL, its credentials and the network path. This is not a clean result |
| 3 | Interrupted, e.g. by `timeout-minutes`, before every technique ran | Partial coverage is not a pass |

## Inputs

| Input | Default | |
|---|---|---|
| `url` | required | The endpoint. Only scan endpoints you are authorised to test |
| `target` | `openai` | `openai`, `json`, `webform`, `echo` (no network, for wiring checks) |
| `model` | | `openai` only: the request's model field |
| `body` / `reply-path` | | `json` only: request template (`{{json}}` is the escaped probe) and dotted path to the reply |
| `field` | | `webform` only: the form field |
| `headers` | | One `Name: value` per line, from secrets |
| `fail-on` | `high` | `critical`, `high`, `medium`, `low`, `none` |
| `rounds` | `1` | Walks of the whole technique set |
| `only` / `exclude` | | Comma-separated technique IDs |
| `context` | | JSON file describing the agent; required by `confirm-url` |
| `confirm-url` / `confirm-model` / `confirm-key` | | Optional model-backed confirmation of each candidate break. Off by default; see [docs/confirm.md](https://github.com/rbrus/sixi-scanner/blob/main/docs/confirm.md) |
| `timeout-minutes` | `60` | Abort after this long; exits 3 |
| `version` | `v0.5.1` | The sixi-scanner tag to build, or `latest` |
| `sarif-path` | `sixi.sarif` | |
| `report-path` | `sixi-report.json` | Full JSON report, transcripts included |

Outputs: `findings`, `gated` (findings at or above `fail-on`), `sarif-path`, `report-path`.

A bespoke agent that does not speak the OpenAI shape:

```yaml
      - uses: rbrus/scan-action@v2
        with:
          target: json
          url: https://internal.example/api/ask
          body: '{"question":{{json}},"session":"ci"}'
          reply-path: answer.text
```

## Keep the report private

The SARIF is what the Security tab shows. The JSON report carries every prompt and every reply the
agent gave, which may include what it leaked. Do not upload it as a public artefact.

## Any other CI

`action/scan.sh` needs only `bash`, `jq` and Go (or a prebuilt binary in `SIXI_SCANNER_BIN`). Set the
`SIXI_*` variables it reads, which mirror the inputs above, and run it from GitLab, Jenkins or a
terminal.

## Upgrading from v1

`v2` runs the scanner locally and its inputs are different: `target` is now the transport and `url`
the endpoint. Moving from `v1` means rewriting the `with:` block.

## Licence

Apache 2.0. See `LICENSE` and `NOTICE`. **Sixi Scanner** is a mark of the author; see the
scanner's [TRADEMARK.md](https://github.com/rbrus/sixi-scanner/blob/main/TRADEMARK.md).
