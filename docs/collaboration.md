# 协作流程

本文件说明 NetMedic 的问题反馈、方案讨论、代码贡献与发布流程。目标：让每一次改动都留下可核查的证据，并始终保持 `main` 可发布。

## 1. 反馈渠道分流

| 你要做什么 | 去哪里 | 说明 |
| --- | --- | --- |
| 使用、装机、网络排查求助 | [Discussions · Q&A](https://github.com/wudicyg/netmedic/discussions/categories/q-a) | 一次性问答，不进入任务列表 |
| 尚未成形的功能想法、方案讨论 | [Discussions · Ideas](https://github.com/wudicyg/netmedic/discussions/categories/ideas) | 讨论清楚后再开 Feature request |
| 已能复现的缺陷 | [Issues · Bug report](https://github.com/wudicyg/netmedic/issues/new?template=bug_report.md) | 必须填写环境、复现步骤与脱敏诊断报告 |
| 目标明确的功能请求 | [Issues · Feature request](https://github.com/wudicyg/netmedic/issues/new?template=feature_request.md) | 必须说明安全影响 |
| 可能被利用的安全问题 | [私密安全报告](https://github.com/wudicyg/netmedic/security/advisories/new) | 不要在公开 Issue 披露利用细节，见 [SECURITY.md](../SECURITY.md) |
| 版本发布公告 | [Discussions · Announcements](https://github.com/wudicyg/netmedic/discussions/categories/announcements) | 每个正式版发布后同步说明 |

**Issue 只用于可执行的任务**：有明确预期行为、可验证的完成条件。开放式问题一律进 Discussions，避免 Issue 列表被讨论淹没。

## 2. Issue 生命周期

1. 提交时选择模板，`bug` / `enhancement` 标签由模板自动带上。
2. 维护者确认范围并补充标签；信息不足或无法复现的会打 `question` 并要求补充诊断报告。
3. 确认后进入开发，PR 描述中用 `Closes #<issue>` 建立关联。
4. PR 合并后 Issue 自动关闭。

## 3. 分支与提交

- 分支命名：`fix/<主题>`、`feat/<主题>`、`docs/<主题>`、`test/<主题>`、`release/<版本>`。
- 提交信息遵循 Conventional Commits：`fix: …`、`feat: …`、`docs: …`、`test: …`、`release: …`。
- **禁止直接向 `main` 推送**，所有改动一律走 PR。
- 分支合并后即删除，不在仓库中长期保留已合并分支。

## 4. PR 门禁

PR 合并前必须满足：

1. 填写 [PR 模板](../.github/PULL_REQUEST_TEMPLATE.md) 中的变更说明、测试、安全、发布相关检查项；
2. CI 全绿——Windows PowerShell 5.1 与 PowerShell 7 两条腿的语法解析 + Pester，以及发布包冒烟测试；
3. 涉及修改系统状态的功能，必须说明备份、验证与回滚路径；
4. 涉及版本变更时同步 README / CHANGELOG；
5. 统一使用 Squash merge，保持 `main` 线性历史。

## 5. 发布流程

1. 在 `main` 上完成版本号与 CHANGELOG 收口：`NetworkRepair.ps1` 中的 `$Script:AppVersion` **必须等于**标签版本。
2. 推送 `v<版本>` 标签，触发 [`.github/workflows/release.yml`](../.github/workflows/release.yml)。
3. 工作流依次：校验标签与版本一致 → 运行 Pester → 构建发布包与 SHA-256 → 创建 GitHub Release。
4. 标签含 `-`（例如 `v1.1.0-beta.1`）会被自动标记为 Prerelease。
5. 发布完成后在 Discussions · Announcements 补充发布说明。

## 6. 敏感信息

任何 Issue、PR、日志或诊断包中都不得包含 Wi-Fi 密码、VPN 凭据、访问令牌、私钥或完整企业网络拓扑。提交诊断信息前请使用一键脱敏诊断包导出器：

```powershell
.\tools\Export-NRSanitizedDiagnosticBundle.ps1
```
