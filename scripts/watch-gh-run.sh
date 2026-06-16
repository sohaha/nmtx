#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: watch-gh-run.sh [run-id]

Environment:
  GH_REPO          GitHub repository to watch. Default: sohaha/nmtx
  GH_WORKFLOW      Workflow file/name used when run-id is omitted. Default: codex.yml
  WATCH_INTERVAL   Poll interval in seconds. Default: 60

The script exits immediately when any job fails, is cancelled, times out, or
requires action. On failure it prints failed-job logs before exiting non-zero.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

repo="${GH_REPO:-sohaha/nmtx}"
workflow="${GH_WORKFLOW:-codex.yml}"
interval="${WATCH_INTERVAL:-60}"
run_id="${1:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 2
fi

if [[ -z "$run_id" ]]; then
  run_id="$(
    gh run list \
      --repo "$repo" \
      --workflow "$workflow" \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId'
  )"
fi

if [[ -z "$run_id" || "$run_id" == "null" ]]; then
  echo "unable to resolve workflow run id for $repo $workflow" >&2
  exit 2
fi

echo "Watching $repo run $run_id"
gh run view "$run_id" --repo "$repo" --json url --jq '.url'

print_jobs() {
  gh run view "$run_id" \
    --repo "$repo" \
    --json jobs \
    --jq '.jobs[] | [.name, .status, (.conclusion // "")] | @tsv'
}

failed_job_ids() {
  gh run view "$run_id" \
    --repo "$repo" \
    --json jobs \
    --jq '.jobs[]
      | select(.conclusion == "failure" or .conclusion == "cancelled" or .conclusion == "timed_out" or .conclusion == "action_required")
      | .databaseId'
}

print_failed_logs() {
  local job_id
  while IFS= read -r job_id; do
    [[ -n "$job_id" ]] || continue
    echo
    echo "===== failed job $job_id logs ====="
    gh run view "$run_id" --repo "$repo" --job "$job_id" --log-failed || true
  done < <(failed_job_ids)
}

while true; do
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  run_state="$(
    gh run view "$run_id" \
      --repo "$repo" \
      --json status,conclusion \
      --jq '[.status, (.conclusion // "")] | @tsv'
  )"
  status="${run_state%%$'\t'*}"
  conclusion="${run_state#*$'\t'}"

  echo
  echo "[$timestamp] status=$status conclusion=${conclusion:-none}"
  print_jobs

  if [[ -n "$(failed_job_ids)" ]]; then
    print_failed_logs
    exit 1
  fi

  if [[ "$status" == "completed" ]]; then
    if [[ "$conclusion" == "success" ]]; then
      echo
      echo "Run completed successfully."
      exit 0
    fi

    echo
    echo "Run completed with conclusion: ${conclusion:-unknown}" >&2
    print_failed_logs
    exit 1
  fi

  sleep "$interval"
done
