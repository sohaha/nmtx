# 交接记录

## 当前焦点

- 更新时间：2026-04-07T06:14:20Z
- 本轮摘要：按用户要求将 `Build Codex Release` 工作流改为“源码统一走 CNB”。`source_ref` 现支持三类输入：分支名、裸 40 位 SHA、完整 CNB commit URL；其中 CNB URL 会被规范化为 commit SHA。`Validate payload` 改为强制 `source_url=https://cnb.cool/zls_nmtx/sohaha/zcodex`，并允许分支名或 SHA。`Validate required secrets` 改为始终要求 `CNB_TOKEN`。

## 待确认问题

- 尚未在 GitHub Actions 上重跑本次新逻辑；当前验证为本地 shell 逻辑校验（main/web/release 分支名、裸 SHA、CNB URL 通过，非法 ref 被拒绝）。

## 下一步检查

- 推送后可用 `source_ref=main` 与 `source_ref=web` 各触发一轮，确认 `build` job 环境中的 `SOURCE_URL` 都是 CNB。
