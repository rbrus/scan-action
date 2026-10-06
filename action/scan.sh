#!/usr/bin/env bash
# Copyright 2026 Radoslaw Brus. SPDX-License-Identifier: Apache-2.0 (LICENSE and NOTICE: github.com/rbrus/scan-action).
#
# The body of the GitHub Action (../action.yml): install sixi-scanner, scan, write SARIF, gate.
#
# Arguments are built as a bash array, never as a string, so a URL, a header or a body template
# cannot break out of the argument it is placed in.
#
# Exit codes are the scanner's: 0 nothing at or above fail-on, 1 findings at or above fail-on,
# 2 the scan could not run, 3 the scan was interrupted before covering what it was asked to cover.
# A pipeline that treats every non-zero as "fix the agent" is wrong about 2 and 3.
set -euo pipefail

target="${SIXI_TARGET:-openai}"
if [ "$target" != echo ]; then
  : "${SIXI_URL:?url is required}"
fi
fail_on="${SIXI_FAIL_ON:-high}"
version="${SIXI_VERSION:-v0.5.1}"
sarif_path="${SIXI_SARIF_PATH:-sixi.sarif}"
report_path="${SIXI_REPORT_PATH:-sixi-report.json}"

case "$fail_on" in
  critical) rank=4 ;; high) rank=3 ;; medium) rank=2 ;; low) rank=1 ;; none) rank=99 ;;
  *) echo "::error::fail-on must be critical, high, medium, low or none (got '$fail_on')"; exit 2 ;;
esac

bin="${SIXI_SCANNER_BIN:-}"
if [ -z "$bin" ]; then
  echo "::group::Install sixi-scanner $version"
  GOBIN="${RUNNER_TEMP:-/tmp}/sixi-bin" go install "github.com/rbrus/sixi-scanner/cmd/sixi-scanner@$version" || {
    echo "::error::could not install sixi-scanner@$version"; exit 2; }
  bin="${RUNNER_TEMP:-/tmp}/sixi-bin/sixi-scanner"
  echo "::endgroup::"
fi

args=(scan --target "$target" --quiet --format json --rounds "${SIXI_ROUNDS:-1}")
[ -n "${SIXI_URL:-}" ]        && args+=(--url "$SIXI_URL")
[ -n "${SIXI_MODEL:-}" ]      && args+=(--model "$SIXI_MODEL")
[ -n "${SIXI_BODY:-}" ]       && args+=(--body "$SIXI_BODY")
[ -n "${SIXI_REPLY_PATH:-}" ] && args+=(--reply-path "$SIXI_REPLY_PATH")
[ -n "${SIXI_FIELD:-}" ]      && args+=(--field "$SIXI_FIELD")
[ -n "${SIXI_ONLY:-}" ]       && args+=(--only "$SIXI_ONLY")
[ -n "${SIXI_EXCLUDE:-}" ]    && args+=(--exclude "$SIXI_EXCLUDE")
[ -n "${SIXI_CONTEXT:-}" ]    && args+=(--context "$SIXI_CONTEXT")
[ -n "${SIXI_CONFIRM_URL:-}" ]   && args+=(--confirm-url "$SIXI_CONFIRM_URL")
[ -n "${SIXI_CONFIRM_MODEL:-}" ] && args+=(--confirm-model "$SIXI_CONFIRM_MODEL")
[ -n "${SIXI_TIMEOUT_MINUTES:-}" ] && args+=(--overall-timeout "${SIXI_TIMEOUT_MINUTES}m")
while IFS= read -r h; do
  h="${h#"${h%%[![:space:]]*}"}"
  [ -n "$h" ] && args+=(--header "$h")
done <<< "${SIXI_HEADERS:-}"

# SIXI_CONFIRM_API_KEY is read by the scanner from the environment, never put on the command line.
set +e
"$bin" "${args[@]}" > "$report_path"
status=$?
set -e

if [ "$status" -ge 2 ]; then
  [ "$status" -eq 3 ] && echo "::error::The scan was interrupted before it covered every technique. Partial coverage is not a pass." \
                      || echo "::error::The scan could not run (exit $status). Check the URL, its credentials and the network path. This is not a clean result."
  exit "$status"
fi

# The scanner lists a technique that got no answer as untested, not as a pass. When nothing answered at
# all, the target was never reached: that is exit 2. The scanner exits 2 itself from v0.5.1; this guard
# covers an older `version`.
techniques=$(jq '.options.techniques | length' "$report_path")
untested=$(jq '.no_answer // [] | length' "$report_path")
if [ "$techniques" -gt 0 ] && [ "$untested" -ge "$techniques" ]; then
  echo "::error::No technique got an answer from $SIXI_URL. The target was never reached. This is not a clean result."
  exit 2
fi
[ "$untested" -gt 0 ] && echo "::warning::$untested of $techniques techniques got no answer and are untested, not passed."

jq -f "$(dirname "$0")/sarif.jq" "$report_path" > "$sarif_path"

findings=$(jq '.findings // [] | length' "$report_path")
gated=$(jq --argjson r "$rank" '
  {"critical":4,"high":3,"medium":2,"low":1,"info":0} as $s
  | [(.findings // [])[] | select(($s[.severity] // 0) >= $r)] | length' "$report_path")

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "findings=$findings"; echo "gated=$gated"
    echo "sarif-path=$sarif_path"; echo "report-path=$report_path"; } >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### sixi-scanner"
    echo
    echo "$findings finding(s); $gated at or above \`$fail_on\`. $untested of $techniques techniques untested."
    echo
    if [ "$findings" -gt 0 ]; then
      echo "| Severity | Technique | Title |"
      echo "|---|---|---|"
      jq -r '.findings[] | "| \(.severity) | `\(.technique_id)` | \(.title) |"' "$report_path"
      echo
    fi
    echo "_A clean result means these probes did not produce a finding. It is not an assurance._"
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "sixi-scanner: $findings finding(s), $gated at or above $fail_on"
[ "$gated" -gt 0 ] && exit 1
exit 0
