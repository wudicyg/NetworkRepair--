# Changelog

## [0.4.0] - 2026-10-08

### Release
- 0.4.0 正式稳定版：核心 Safe Repair、历史编号 Profile 清理、scoped Backup/Restore、诊断与回滚路径已收口。
- Windows 10 / PowerShell 5.1 完成核心实机行为验证；Windows 11 与更多环境作为后续扩展验证，不阻塞本版本发布。

## [0.4.0-dev]

### Added
- 独立修复决策计划层，统一 Dry Run 与真实修复路径。
- Deep Repair 在无可删除 Profile 时仍可明确执行 `NewNetworks` 刷新。
- Restore 完成注册表快照校验；校验失败时自动回到恢复前安全备份并再次验证。
- 增加修复计划与注册表快照比较回归测试。
- 网络健康状态与 Profile 历史遗留独立判断；健康网络仍可生成历史 Profile 清理计划。
- 健康网络且无安全清理候选时明确返回 NoAction，不进入修改路径。
- 一键脱敏诊断包导出器，仅保留发布验收和故障排查所需的非敏感摘要。
- 标准发布包构建器与 Tag 驱动的 GitHub Release 自动化。
- 交互式菜单增加只读快速状态概览，区分当前网络健康度、可安全清理的历史编号 Profile 与受保护编号 Profile。

### Changed
- 人类可读诊断报告现在会明确显示非致命诊断阶段的降级提示，并继续允许完成其余可用诊断。
- 脱敏诊断包工具从入口脚本自动读取应用版本，避免开发版本号漂移。
- 开发版本 Tag（例如 `v0.4.0-dev`）由 Release 工作流自动标记为 Prerelease，并在创建 Release 前验证 Tag。
- Release 发布流程补充文档，明确合并 `main` 不会自动创建 GitHub Release。
- CI 增加 Release 工作流关键安全开关的静态回归检查。
- 备份与发布验收文档现在明确区分完整 `NetworkList.reg` 基线快照与 Restore 实际导入的 `Profiles` / `NewNetworks` managed scopes。
- 0.4.0 稳定版收口发布门槛：核心 Windows 10 实机行为作为主要验收依据，Windows 11/更多环境转为后续扩展验证。

### Fixed
- Deep Repair 在网络健康且没有可安全清理 Profile 时不再生成破坏性 `NewNetworks` 刷新动作。
- 注册表 Profile 扫描容忍缺失的可选 `ProfileName`、`Description`、`Category`、`Managed` 属性。
- 修复脱敏诊断包对 `网络 N` / `Network N` 编号 Profile 的分类与计数正则。
- 扫描兼容缺失 `LastWriteTime` 的 Registry Provider 对象。
- NLM COM 不可用时降级为 PowerShell / 注册表诊断，不阻断 Scan。
- 兼容缺失 `IPv4Address` 属性的网络接口对象。
- 隔离可选诊断阶段，避免单项网络组件异常中止整次扫描。
- Safe Repair 显示备份、删除、服务处理、验证与自动回滚进度，并输出最终结果。

## [0.3.0-dev]

### Added
- Registry Profile GUID 与 Network List Manager NetworkId 精确关联。
- 显式 NetworkId 网络重命名命令。
- 重命名前自动备份，修改后验证，失败自动恢复。
- Windows 网络名称输入规则验证。

## [0.2.0] - 2026-10-08

### Added
- Network List Manager COM 网络对象诊断。
- Profile 风险评分、风险等级和可解释诊断码。
- IP / DHCP / 默认网关 / DNS 诊断。
- NCSI DNS 与 HTTP Web Probe 诊断。

### Changed
- Safe Repair 改为依据 `RemediationAllowed` 安全门槛执行。
- 修复后验证增加 IP 与默认网关完整性检查。


## [0.1.1] - 2026-10-08

### Fixed
- 恢复备份前自动创建当前状态安全备份
- 恢复失败时尝试回滚到恢复前状态
- 诊断报告移至独立 reports/ 目录

## [0.1.0] - 2026-10-08

### Added
- 模块化 PowerShell 架构
- BAT 兼容入口
- 管理员权限检查
- 自动诊断、Safe Repair、Deep Repair、Dry Run
- Registry Backup / Restore
- 修复后验证与失败自动回滚
- 日志、JSON 报告、Pester 测试

### Changed
- 默认不清空 NetworkList Signatures
- 默认不删除当前活动 Profile
- 支持中文与英文编号网络名称
