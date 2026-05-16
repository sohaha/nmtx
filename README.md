# nmtx

CI/workflow repository for building and publishing `@sohaha/zcodex` release assets.

## zcodex release size policy

`Build Codex Release` (`.github/workflows/codex.yml`) keeps release binaries size-sensitive by default:

- Linux x64 musl release builds use fat LTO, `codegen-units=1`, symbol stripping, `panic=abort`, and `opt-level=s`.
- The Linux x64 musl `codex` binary budget is `190000000` bytes, enforced both on build artifacts and npm package staging.
- macOS arm64 and Windows arm64 still have platform-specific budgets in the workflow; do not loosen them to hide regressions.

Known npm baseline used during the 2026-05 size investigation:

| Package version | linux-x64 `codex` binary |
| --- | ---: |
| `1.0.5-linux-x64` | `189,092,976` bytes |
| `1.0.18-linux-x64` | `213,357,680` bytes |
| `1.1.0-linux-x64` | `263,485,376` bytes |

The `1.1.0` jump was caused by disabling LTO for `x86_64-unknown-linux-musl`; do not disable LTO for that target without replacing the size gate with an equivalent verified strategy.

## Optional AWS auth feature

The zcodex source can make AWS Bedrock/SigV4 auth dependencies optional to keep default release packages small. The release workflow exposes this as:

```text
enable_aws_auth=false
```

Default release builds leave it disabled and therefore do not pass `--features aws-auth` to the `codex` binary build. Set `enable_aws_auth=true` only for releases that intentionally include the AWS SDK auth stack (`aws-config`, `aws-sdk-*`, `aws-smithy-*`).

`enable_semantic_embeddings=false` is also the default. Set it to `true` only when the release intentionally bundles ztldr semantic embedding support and accepts the extra `fastembed` / ONNX Runtime / tokenizer dependency stack.

Example manual smoke build with AWS auth enabled:

```bash
gh workflow run codex.yml \
  -R sohaha/nmtx \
  -r fix/linux-musl-thin-lto-size \
  -f version=1.1.6-linux-x64-aws-auth \
  -f source_ref=fix/default-disable-aws-auth-size \
  -f targets=x86_64-unknown-linux-musl \
  -f release_repo=sohaha/zcodex \
  -f publish_mode=build-only \
  -f enable_aws_auth=true
```
