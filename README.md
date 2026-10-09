# nmtx

用于保存 CNB/nmtx 发布流水线所需的 GitHub Actions 工作流与辅助脚本。

- `.cnb.yml` 负责把 CNB 的 `main` 与 tag 同步到 GitHub。
- `.github/workflows/zkey.yml` 支持 `repository_dispatch`、`workflow_dispatch`，也会在
  GitHub 收到 `v*` tag push 时自动构建并发布到 `https://releases.73zls.com/zkey`。
- `nmtx/.github/workflows/ai-transfer.yml` 支持 `repository_dispatch`（`build-ai-transfer-release`）
  与 `workflow_dispatch`。从 `sohaha/ai-transfer` 按精确 SHA 拉取源码，交叉编译
  Linux / macOS / Windows 二进制（内嵌 web UI），创建 GitHub release，并把同一组资产
  （二进制、`SHA256SUMS`、`install.sh` / `install.ps1` / `uninstall.sh` / `uninstall.ps1`、
  `README.md`、`latest.json`）上传到 `https://releases.73zls.com/ai-transfer/`。
  `latest.json` 是应用内更新检查读取的唯一清单，用 `no-cache, must-revalidate` 每次回源。
  源仓侧用 `mise run release -- --bump patch`（或 `--version X.Y.Z`）触发。

## Zeno 服务端 + 客户端统一发布

默认入口为 `.github/workflows/zeno-release.yml`（**Build Zeno Release**）：

1. `scripts/zeno-resolve-source.sh` 将源仓 `zls_nmtx/sohaha/bots` 的分支、tag、SHA 或
   CNB commit URL 固定为一个 commit SHA，避免两端构建期间分支移动造成版本不一致。
2. 同一次 workflow run 并行调用 `zeno-server.yml` 和 `zeno-computer.yml`，共用
   `source_ref`、`version`、`channel`、`publish`、`retain`、`github_release` 参数。
3. 每端构建五目标 SEA 矩阵（linux x64/arm64、win32 x64、darwin arm64/x64）；
   服务端还会构建并内嵌 web UI。
4. 服务端发布到 `https://releases.73zls.com/zeno/server/`，客户端发布到
   `https://releases.73zls.com/zeno/`。制品名称和并发组按产品隔离。

**两端上传独立执行，不是原子发布**：一端失败不会回滚另一端；修复后可重跑失败任务，
或用相同 SHA 和版本号单独发布失败的一端。`--github-release` 只为客户端创建额外的
GitHub release，服务端接受但忽略此选项。

源仓调用（版本默认读取 `packages/computer/package.json`，作为两端共用的发布版本）：

```bash
# 只打印请求，不触发发布
mise run nmtx:ci -- --version 0.0.1 --dry-run
# 同一次 run 构建发布两端；默认源码 HEAD 必须先推到 CNB
mise run nmtx:ci -- --version 0.0.1
# 两端只构建，不上传 R2
mise run nmtx:ci -- --version 0.0.1 --no-publish
# 保留独立发布入口
mise run nmtx:ci -- --workflow zeno-server.yml --version 0.0.1
mise run nmtx:ci -- --workflow zeno-computer.yml --version 0.0.1
```

也可以在 GitHub Actions 页面直接运行 **Build Zeno Release**。
两个产品工作流均保留 `workflow_dispatch` 和 `repository_dispatch`
（`build-zeno-server-release` / `build-zeno-computer-release`），并提供 `workflow_call`。

复用调用通过 `secrets: inherit` 使用仓库中已有的 `CNB_TOKEN`、
`CLOUDFLARE_API_TOKEN`、`CODEBAY_RELEASE_WRITE_TOKEN`（客户端 GH release 时使用），
以及仓库变量 `CLOUDFLARE_ACCOUNT_ID`。现有子流程仍会检查 Cloudflare 配置，
因此 `--no-publish` 也需要现有配置。

## R2 安装脚本与说明文档

每次发布都会从同一源码提交复制两端 `install.sh`、`install.ps1` 与安装说明：

| 产品 | 文档源码（zbot 仓库） | R2 README |
| --- | --- | --- |
| 服务端 | `packages/server/RELEASE_README.md` | <https://releases.73zls.com/zeno/server/README.md> |
| 客户端 | `packages/computer/RELEASE_README.md` | <https://releases.73zls.com/zeno/README.md> |

安装脚本位于对应 README 的同级目录。`scripts/release-ci.mjs` 通过 `--readme`
传入产品说明，`scripts/prepare-zeno-release.mjs` 将其复制为发布树根目录的 `README.md`；
缺失文档会使打包失败。上传使用 `text/markdown; charset=utf-8` 和
`no-cache, must-revalidate`，不会把可变根文档标记为一年不可变缓存。
源码提交记录在各自的 `<version>/provenance.txt`，不是发布根目录。

注意：默认发布构建产物；仅 `--no-publish` 会跳过 R2。版本化产物采用 immutable 缓存，
覆盖同一版本不是常规升级路径，边缘缓存或本地缓存可能仍保留旧字节；正常发布应递增版本。

## 同步与验证

同步到 `github.com/sohaha/nmtx` 时需包含完整工作流和依赖：

- `.github/workflows/zkey.yml`
- `.github/scripts/prepare-r2-release-assets.mjs`
- `.github/workflows/zeno-release.yml`
- `.github/workflows/zeno-server.yml`
- `.github/workflows/zeno-computer.yml`
- `scripts/zeno-resolve-source.sh`
- `.github/workflows/ai-transfer.yml`（ai-transfer 发布流水线）
- `.github/workflows/zcode.yml`
- `.github/scripts/prepare-zcode-release-assets.mjs`
- `.github/release-assets/zcode/README.md`、`install.sh`（发布时随产物上传到 R2 `zcode/` 前缀）

远端仓库已存在 `.github/actions/macos-code-sign/signing_helpers.sh`，当前 `zkey.yml` 直接复用它。

```bash
gh api repos/sohaha/nmtx/actions/workflows --jq '.workflows[] | {path,state}'
```

本仓离线回归检查（不访问 GitHub、CNB 或 R2）：

```bash
# 需要 Python 3 + PyYAML
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_zeno_release.py'
bash -n scripts/zeno-resolve-source.sh
# 安装 actionlint 后检查工作流语法、复用输入与权限
actionlint -shellcheck= -pyflakes= .github/workflows/zeno-{release,server,computer}.yml
```
