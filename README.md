# NetworkRepair

安全、智能、可回滚的 Windows 网络配置诊断与修复工具。

> 当前稳定版本：**0.2.0**

当前主分支：**0.4.0-dev（已合并 Repair Planner 与 Restore 快照校验能力，待实机验证）**

NetworkRepair 的目标不是“暴力清理注册表”，而是：

**先诊断 → 先备份 → 再修改 → 最后验证 → 失败回滚。**

## 当前能力

- 自动检查 Windows 版本、网络适配器和当前 Connection Profile
- 扫描 `NetworkList\Profiles` 并识别低风险/高风险候选
- 中文与英文的编号网络名称识别，例如 `网络 3` / `Network 3`
- 默认不会删除当前活动 Profile
- 默认不会清理 `Signatures\Managed` / `Signatures\Unmanaged`
- 修复前自动创建带时间戳的完整 `NetworkList.reg` 备份
- Dry Run：只显示操作计划，不修改系统
- 修复后重新扫描并进行连通性验证
- 验证失败自动尝试回滚
- JSON 诊断报告
- CLI 模式与交互式菜单
- Pester 安全规则测试
- Network List Manager COM 交叉诊断
- 风险评分与可解释诊断码
- IP / DHCP / 默认网关 / DNS 诊断
- NCSI DNS / HTTP 探测
- Profile GUID ↔ NetworkId 精确关联
- 基于 Network List Manager 的显式网络重命名
- 独立 Repair Planner：统一 Dry Run 与真实修复的操作计划
- Deep Repair 在无可删除 Profile 时仍可明确刷新 `NewNetworks`
- Restore 导入后进行 `NetworkList.reg` 快照校验，失败自动回到恢复前安全备份
- 网络健康与 Profile 历史遗留分离判断：网络健康时仍会识别并处理 `网络 2/3/4...` 历史 Profile

## 快速开始

双击：

```text
NetworkRepair.bat
```

命令行：

```bat
NetworkRepair.bat -Mode Scan
NetworkRepair.bat -Mode DryRun
NetworkRepair.bat -Mode Repair
NetworkRepair.bat -Mode DeepRepair
NetworkRepair.bat -Mode Backup
NetworkRepair.bat -Mode Report
NetworkRepair.bat -Mode Rename -NetworkId "{GUID}" -NewName "Office"
```

JSON：

```bat
NetworkRepair.bat -Mode Scan -Json
```

跳过 Internet/DNS 测试：

```bat
NetworkRepair.bat -Mode Scan -SkipConnectivityTest
```

## 安全模型

### Safe Repair

默认只自动处理：

1. 名称匹配 `网络 N` 或 `Network N`；
2. 不是当前活动连接；
3. 不属于 Managed 配置。

### Deep Repair

在 Safe Repair 基础上刷新 `NewNetworks`。v0.2.0 **不会**无条件删除 `Signatures\Managed` / `Signatures\Unmanaged`，因为这些签名数据可能参与网络识别，尤其在企业环境中不适合默认破坏。

## 备份

每次真正修改前创建：

```text
backups/
  20261008_013521_123/
    NetworkList.reg
    diagnostic.json
    manifest.json
```

可以恢复：

```bat
NetworkRepair.bat -Mode Restore -BackupPath "backups\20261008_013521_123" -Yes
```

## 日志

运行日志位于：

```text
logs/
```

默认不会写入 Wi-Fi 密码等凭据。

## 项目结构

```text
NetworkRepair/
├─ NetworkRepair.bat
├─ NetworkRepair.ps1
├─ src/
│  ├─ Common.ps1
│  ├─ Diagnostics.ps1
│  ├─ NetworkListManager.ps1
│  ├─ NetworkIdentity.ps1
│  ├─ RepairPlan.ps1
│  ├─ Ncsi.ps1
│  ├─ Backup.ps1
│  ├─ Repair.ps1
│  └─ Validation.ps1
├─ tests/
│  └─ NetworkRepair.Tests.ps1
├─ docs/
├─ backups/
├─ logs/
├─ README.md
├─ LICENSE
├─ CHANGELOG.md
├─ CONTRIBUTING.md
└─ SECURITY.md
```

## 系统要求

- Windows 10 / Windows 11
- Windows PowerShell 5.1
- 管理员权限

NetworkRepair 使用 Windows `NetConnection` 模块获取 Connection Profile，并以 Network List Manager 所提供的网络信息模型为设计依据。

## 开发文档

- [架构设计](docs/architecture.md)
- [路线图](docs/roadmap.md)
- [诊断代码](docs/diagnostic-codes.md)

## 项目路线

当前 `main` 已包含 v0.4 的 Repair Planner、Restore 快照校验和“网络健康 / Profile 历史遗留”双轨判定。正式稳定版仍需完成 Windows 10 / 11 实机矩阵、更多语言环境和发布包验证。后续重点是 TUI 增强、脱敏诊断包和多级恢复点。

## License

MIT
