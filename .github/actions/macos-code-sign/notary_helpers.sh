retry_notary_command() {
  local label="$1"
  shift

  local attempt=1
  local max_attempts=3
  local sleep_seconds=15
  local output
  local exit_code

  while true; do
    if output=$("$@" 2>&1); then
      printf '%s\n' "$output"
      return 0
    fi

    exit_code=$?
    printf '%s\n' "$output" >&2

    if (( attempt >= max_attempts )); then
      return "$exit_code"
    fi

    echo "::warning title=Notary retry::${label} attempt ${attempt}/${max_attempts} failed, retrying in ${sleep_seconds}s" >&2
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
    sleep_seconds=$((sleep_seconds * 2))
  done
}

notarize_submission() {
  local label="$1"
  local path="$2"
  local notary_key_path="$3"

  if [[ -z "${APPLE_NOTARIZATION_KEY_ID:-}" || -z "${APPLE_NOTARIZATION_ISSUER_ID:-}" ]]; then
    echo "APPLE_NOTARIZATION_KEY_ID and APPLE_NOTARIZATION_ISSUER_ID are required for notarization"
    exit 1
  fi

  if [[ -z "$notary_key_path" || ! -f "$notary_key_path" ]]; then
    echo "Notary key file $notary_key_path not found"
    exit 1
  fi

  if [[ ! -f "$path" ]]; then
    echo "Notarization payload $path not found"
    exit 1
  fi

  local submission_json
  submission_json=$(retry_notary_command "$label notarization" \
    xcrun notarytool submit "$path" \
      --key "$notary_key_path" \
      --key-id "$APPLE_NOTARIZATION_KEY_ID" \
      --issuer "$APPLE_NOTARIZATION_ISSUER_ID" \
      --output-format json \
      --wait)

  local status submission_id
  status=$(printf '%s\n' "$submission_json" | jq -r '.status // "Unknown"')
  submission_id=$(printf '%s\n' "$submission_json" | jq -r '.id // ""')

  if [[ -z "$submission_id" ]]; then
    echo "Failed to retrieve submission ID for $label"
    exit 1
  fi

  echo "::notice title=Notarization::$label submission ${submission_id} completed with status ${status}"

  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed for ${label} (submission ${submission_id}, status ${status})"
    exit 1
  fi
}
