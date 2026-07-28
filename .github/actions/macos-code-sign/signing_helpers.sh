decode_base64_file() {
  local value="$1"
  local output_path="$2"

  if printf '%s' "$value" | base64 --decode > "$output_path" 2>/dev/null; then
    return 0
  fi
  if printf '%s' "$value" | base64 -d > "$output_path" 2>/dev/null; then
    return 0
  fi
  printf '%s' "$value" | base64 -D > "$output_path"
}

configure_apple_code_signing() {
  local certificate="$1"
  local certificate_password="$2"
  local cert_path="$3"
  local keychain_path="$4"
  local keychain_password="$5"

  if [[ -z "$certificate" ]]; then
    echo "APPLE_CERTIFICATE is required for macOS signing"
    return 1
  fi
  if [[ -z "$certificate_password" ]]; then
    echo "APPLE_CERTIFICATE_PASSWORD is required for macOS signing"
    return 1
  fi

  decode_base64_file "$certificate" "$cert_path"
  security create-keychain -p "$keychain_password" "$keychain_path"
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain -p "$keychain_password" "$keychain_path"

  local keychain_args=()
  while IFS= read -r keychain; do
    [[ -n "$keychain" ]] && keychain_args+=("$keychain")
  done < <(security list-keychains | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"//g')

  if ((${#keychain_args[@]} > 0)); then
    security list-keychains -s "$keychain_path" "${keychain_args[@]}"
  else
    security list-keychains -s "$keychain_path"
  fi

  security default-keychain -s "$keychain_path"
  security import "$cert_path" \
    -k "$keychain_path" \
    -P "$certificate_password" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
  security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$keychain_password" \
    "$keychain_path" > /dev/null

  local codesign_hashes=()
  while IFS= read -r hash; do
    [[ -n "$hash" ]] && codesign_hashes+=("$hash")
  done < <(
    security find-identity -v -p codesigning "$keychain_path" |
      sed -n 's/.*\([0-9A-F]\{40\}\).*/\1/p' |
      sort -u
  )

  rm -f "$cert_path"

  if ((${#codesign_hashes[@]} == 0)); then
    echo "No signing identities found in $keychain_path"
    remove_apple_signing_keychain "$keychain_path"
    return 1
  fi
  if ((${#codesign_hashes[@]} > 1)); then
    echo "Multiple signing identities found in $keychain_path:"
    printf '  %s\n' "${codesign_hashes[@]}"
    remove_apple_signing_keychain "$keychain_path"
    return 1
  fi

  APPLE_CODESIGN_IDENTITY="${codesign_hashes[0]}"
  APPLE_CODESIGN_KEYCHAIN="$keychain_path"
}

remove_apple_signing_keychain() {
  local keychain_path="$1"
  [[ -n "$keychain_path" ]] || return 0

  local keychain_args=()
  while IFS= read -r keychain; do
    [[ "$keychain" == "$keychain_path" ]] && continue
    [[ -n "$keychain" ]] && keychain_args+=("$keychain")
  done < <(security list-keychains | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"//g')

  if ((${#keychain_args[@]} > 0)); then
    security list-keychains -s "${keychain_args[@]}"
    security default-keychain -s "${keychain_args[0]}"
  else
    security list-keychains -s
  fi

  if [[ -f "$keychain_path" ]]; then
    security delete-keychain "$keychain_path"
  fi
}

strip_wrapping_quotes() {
  local value="$1"
  local first_char last_char

  if ((${#value} >= 2)); then
    first_char="${value:0:1}"
    last_char="${value: -1}"
    if [[ ("$first_char" == '"' || "$first_char" == "'") && "$first_char" == "$last_char" ]]; then
      printf '%s' "${value:1:${#value}-2}"
      return 0
    fi
  fi
  printf '%s' "$value"
}

validate_notary_key_path() {
  local candidate_path="$1"
  local normalized_path="${candidate_path}.normalized"
  local pem_path="${candidate_path}.pem"

  if openssl pkey -in "$candidate_path" -inform PEM -noout >/dev/null 2>&1; then
    echo "::notice title=Notary key::validated notary key as PEM"
    return 0
  fi

  LC_ALL=C tr -d '\r' < "$candidate_path" > "$normalized_path"
  if openssl pkey -in "$normalized_path" -inform PEM -noout >/dev/null 2>&1; then
    mv "$normalized_path" "$candidate_path"
    echo "::notice title=Notary key::validated notary key as PEM after CRLF normalization"
    return 0
  fi
  rm -f "$normalized_path"

  if openssl pkey -in "$candidate_path" -inform DER -noout >/dev/null 2>&1; then
    openssl pkcs8 -inform DER -outform PEM -nocrypt -in "$candidate_path" -out "$pem_path" >/dev/null 2>&1
    mv "$pem_path" "$candidate_path"
    echo "::notice title=Notary key::converted DER notary key to PEM"
    return 0
  fi

  rm -f "$pem_path"
  return 1
}

write_notary_text_candidate() {
  local value="$1"
  local target_path="$2"
  local label="$3"
  local normalized_value

  normalized_value="$(strip_wrapping_quotes "$value")"
  normalized_value="${normalized_value//\\r\\n/$'\n'}"
  normalized_value="${normalized_value//\\n/$'\n'}"
  normalized_value="${normalized_value//\\r/$'\r'}"

  printf '%s\n' "$normalized_value" > "$target_path"
  echo "::notice title=Notary key::$label"
}

try_decoded_notary_text_variants() {
  local candidate_path="$1"
  local target_path="$2"
  local decoded_text compact_text

  LC_ALL=C grep -q '[^[:print:][:space:]]' "$candidate_path" && return 1
  decoded_text="$(<"$candidate_path")"

  write_notary_text_candidate "$decoded_text" "$target_path" "normalized decoded notary key text"
  if validate_notary_key_path "$target_path"; then
    return 0
  fi

  compact_text="$(printf '%s' "$decoded_text" | tr -d '[:space:]')"
  if [[ "$compact_text" =~ ^[A-Za-z0-9+/=]+$ ]] && decode_base64_file "$compact_text" "$target_path"; then
    echo "::notice title=Notary key::decoded nested base64 notary key payload"
    if validate_notary_key_path "$target_path"; then
      return 0
    fi
  fi

  return 1
}

write_notary_key() {
  local raw_secret="$1"
  local output_path="$2"
  local unquoted_secret

  unquoted_secret="$(strip_wrapping_quotes "$raw_secret")"

  if decode_base64_file "$raw_secret" "$output_path"; then
    echo "::notice title=Notary key::decoded APPLE_NOTARIZATION_KEY_P8 as base64"
    if validate_notary_key_path "$output_path" || try_decoded_notary_text_variants "$output_path" "$output_path"; then
      return 0
    fi
  fi

  if [[ "$unquoted_secret" != "$raw_secret" ]] && decode_base64_file "$unquoted_secret" "$output_path"; then
    echo "::notice title=Notary key::decoded quoted APPLE_NOTARIZATION_KEY_P8 as base64"
    if validate_notary_key_path "$output_path" || try_decoded_notary_text_variants "$output_path" "$output_path"; then
      return 0
    fi
  fi

  write_notary_text_candidate "$raw_secret" "$output_path" "wrote raw APPLE_NOTARIZATION_KEY_P8"
  if validate_notary_key_path "$output_path"; then
    return 0
  fi

  if [[ "$unquoted_secret" != "$raw_secret" ]]; then
    write_notary_text_candidate "$unquoted_secret" "$output_path" "wrote unquoted APPLE_NOTARIZATION_KEY_P8"
    if validate_notary_key_path "$output_path"; then
      return 0
    fi
  fi

  echo "APPLE_NOTARIZATION_KEY_P8 did not decode to a valid PEM or DER private key"
  return 1
}
