#!/usr/bin/env bash
set -euo pipefail

# Print only the immutable commit SHA to stdout; never log credentials.
: "${CNB_TOKEN:?CNB_TOKEN is required}"
: "${SOURCE_REF:?SOURCE_REF is required}"
source_url="${SOURCE_URL:-https://cnb.cool/zls_nmtx/sohaha/bots}"
source_ref="$SOURCE_REF"
if [[ "$source_ref" =~ ^https://cnb\.cool/zls_nmtx/sohaha/bots/-/commit/([0-9a-f]{40})/?$ ]]; then
  source_ref="${BASH_REMATCH[1]}"
fi
[[ "$source_ref" =~ ^[0-9A-Za-z][0-9A-Za-z._/-]*$ ]] || {
  echo "Unsupported source ref: $source_ref" >&2
  exit 1
}

basic_auth_token="$(printf 'cnb:%s' "$CNB_TOKEN" | base64 | tr -d '\n')"
worktree="$(mktemp -d)"
trap 'rm -rf "$worktree"' EXIT
git init -q "$worktree"
git -C "$worktree" \
  -c credential.helper= \
  -c core.askPass= \
  -c "http.extraHeader=AUTHORIZATION: basic ${basic_auth_token}" \
  fetch --quiet --depth=1 "$source_url" "$source_ref"
# Peel annotated tags, so both products receive a commit rather than a tag SHA.
source_sha="$(git -C "$worktree" rev-parse 'FETCH_HEAD^{commit}')"
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Unable to resolve source ref: $source_ref" >&2
  exit 1
}
printf '%s\n' "$source_sha"
