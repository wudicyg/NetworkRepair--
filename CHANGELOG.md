# Changelog

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
