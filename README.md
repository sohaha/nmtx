# nmtx

用于保存 CNB/nmtx 发布流水线所需的 GitHub Actions 工作流与辅助脚本。

- `.cnb.yml` 负责把 CNB 的 `main` 与 tag 同步到 GitHub。
- `nmtx/.github/workflows/zkey.yml` 支持 `repository_dispatch`、`workflow_dispatch`，也会在
  GitHub 收到 `v*` tag push 时自动构建并发布到 `https://releases.73zls.com/zkey`。
- `nmtx/.github/workflows/zeno-computer.yml` 支持 `repository_dispatch`（`build-zeno-computer-release`）
  与 `workflow_dispatch`。从 `zls_nmtx/sohaha/bots` 按精确 SHA 拉取源码，用
  `packages/computer/scripts/native/build.mjs` 构建五目标 SEA 矩阵
  （linux x64/arm64、win32 x64、darwin arm64/x64），由源仓
  `scripts/prepare-zeno-release.mjs` 组装发布树并上传到
  `https://releases.73zls.com/zeno/`（`manifest.json` 通道指针、
  `versions.json` 索引、`<version>/` 产物与 manifest、`install.sh`/`install.ps1`）。
  源仓侧用 `mise run nmtx:ci` 触发。

同步到 `github.com/sohaha/nmtx` 时，至少需要把以下文件放到远端仓库根目录：

- `.github/workflows/zkey.yml`
- `.github/scripts/prepare-r2-release-assets.mjs`
- `.github/workflows/zeno-computer.yml`（zeno-computer SEA 发布流水线）

远端仓库已存在 `.github/actions/macos-code-sign/signing_helpers.sh`，当前 `zkey.yml` 直接复用它。

同步完成后可先验证：

```bash
gh api repos/sohaha/nmtx/actions/workflows --jq '.workflows[] | {path,state}'
```

看到 `.github/workflows/zkey.yml` 后，再回到本仓运行：

```bash
mise run nmtx:ci -- --dry-run
mise run nmtx:ci
```
