# Changelog

## [0.4.0-dev]

### Added
- 独立修复决策计划层，统一 Dry Run 与真实修复路径。
- Deep Repair 在无可删除 Profile 时仍可明确执行 `NewNetworks` 刷新。
- Restore 完成注册表快照校验；校验失败时自动回到恢复前安全备份并再次验证。
- 增加修复计划与注册表快照比较回归测试。
- 网络健康状态与 Profile 历史遗留独立判断；健康网络仍可生成历史 Profile 清理计划。
- 健康网络且无安全清理候选时明确返回 NoAction，不进入修改路径。

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
