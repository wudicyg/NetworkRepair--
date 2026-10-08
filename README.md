# NetworkRepair

安全、智能、可回滚的 Windows 网络配置诊断与修复工具。

> 当前稳定版本：**1.0.0**
>
> `1.0.0` 为项目首个正式稳定版。核心 Safe Repair、历史编号 Profile 清理、Backup/Restore、诊断与回滚路径已完成收口，并已在真实 Windows 10 / PowerShell 5.1 环境完成核心行为验证。Windows 11 及更多语言/系统组合保留为后续兼容性扩展验证。

> **项目定位**：专门解决 Windows 网络名称持续出现「网络 2 / 网络 3 / 网络 4 / …」等历史 Network Profile 累积问题。  
> 在不破坏当前活动网络的前提下，先诊断、再备份、后清理并验证；同时提供 DNS、DHCP、网关、NCSI 等常见网络故障诊断与可回滚修复能力。

当前主分支：**1.0.0**

NetworkRepair 的目标不是“暴力清理注册表”，而是：

**先诊断 → 先备份 → 再修改 → 最后验证 → 失败回滚。**

## 项目定位

NetworkRepair 的核心任务不是“重置整个网络”，而是解决 Windows 长期使用后不断累积的编号网络 Profile，例如 `网络 2`、`网络 3`、`网络 4`、`Network 2` 等历史遗留项。

网络连通性诊断与修复属于配套能力：当网络本身正常时，工具不会为了测试而盲目修改系统；当网络正常但存在符合安全规则的历史编号 Profile 时，仍会独立识别并提供清理计划。

## 当前能力

- 自动检查 Windows 版本、网络适配器和当前 Connection Profile
- 扫描 `NetworkList\\Profiles` 并识别低风险/高风险候选
- 中文与英文的编号网络名称识别，例如 `网络 3` / `Network 3`
- 默认不会删除当前活动 Profile
- 默认不会清理 `Signatures\\Managed` / `Signatures\\Unmanaged`
- 修复前自动创建带时间戳的完整 `NetworkList.reg` 备份，同时保存 Restore 所需的 scoped `Profiles` / `NewNetworks` 快照
- 修复后重新扫描并进行连通性验证
- 验证失败自动尝试回滚
- JSON 诊断报告
- 只读发布验收证据采集器
- CLI 模式与交互式菜单
- Pester 安全规则测试
- Network List Manager COM 交叉诊断
- 风险评分与可解释诊断码
- IP / DHCP / 默认网关 / DNS 诊断
- NCSI DNS / HTTP 探测
- Profile GUID ↔ NetworkId 精确关联
- 基于 Network List Manager 的显式网络重命名
- 独立 Repair Planner：统一修复决策与真实执行计划
- Deep Repair 在无可删除 Profile 时仍可明确刷新 `NewNetworks`
- Restore 只导入 NetworkRepair 管理的 `Profiles` / `NewNetworks` 范围，完成 scoped 快照校验；失败自动回到恢复前安全备份
- 网络健康与 Profile 历史遗留分离判断：网络健康时仍会识别并处理 `网络 2/3/4...` 历史 Profile
- 交互式菜单进入时提供只读快速状态概览，不触发 NCSI 主动探测；Repair 前仍执行完整重新诊断

## 快速开始

双击：

```text
NetworkRepair.bat
```

命令行：

```bat
NetworkRepair.bat -Mode Scan
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

导出脱敏诊断包（只读，不包含机器名、MAC、IP、NetworkId 或注册表备份）：

```bat
powershell.exe -ExecutionPolicy Bypass -File .\\tools\\Export-NRSanitizedDiagnosticBundle.ps1
```

构建发布包（开发者/维护者）：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\\tools\\New-NRReleasePackage.ps1
```

发布包由带 `v` 前缀的版本 Tag 触发 GitHub Actions 自动构建，并生成 ZIP 与 SHA-256 校验文件。发布 Tag 必须与 `NetworkRepair.ps1` 中的版本完全一致。

跳过 Internet/DNS 测试：

```bat
NetworkRepair.bat -Mode Scan -SkipConnectivityTest
```


## 发布流程

GitHub Release 不会因为合并到 `main` 自动产生；只有推送与 `NetworkRepair.ps1` 版本完全一致的 Tag 后，Release 工作流才会创建发行版。

当前稳定版为：

```text
1.0.0
```

正式稳定版本 Tag：

```powershell
git tag v1.0.0
git push origin v1.0.0
```

发布工作流会把与应用版本完全一致的 Tag 作为正式 Release 构建。后续开发版本从 `1.1.0-dev` 开始。

Release 工作流会在发布前执行 PowerShell 5.1 / PowerShell 7 所需的 Pester 测试、构建 Windows ZIP、生成 SHA-256 校验文件，并校验 Tag 与应用版本是否完全一致。当前版本以 Windows 10 实机核心场景为主要行为证据，Windows 11 与更多环境组合属于后续扩展验证。
## 安全模型

### Safe Repair

默认只自动处理：

1. 名称匹配 `网络 N` 或 `Network N`；
2. 不是当前活动连接；
3. 不属于 Managed 配置。

### Deep Repair

在 Safe Repair 基础上刷新 `NewNetworks`。当前稳定版 **不会**无条件删除 `Signatures\\Managed` / `Signatures\\Unmanaged`，因为这些签名数据可能参与网络识别，尤其在企业环境中不适合默认破坏。

## 备份

每次真正修改前创建一个带时间戳的目录，例如：

```text
backups/
  20261008_190429_297/
    NetworkList.reg
    NetworkList-Profiles.reg
    NetworkList-NewNetworks.reg
    diagnostic.json
    manifest.json
```

其中：

- `NetworkList.reg`：完整 `NetworkList` 树的只读基线快照，用于审计与故障排查。
- `NetworkList-Profiles.reg`：Restore 实际导入和校验的 `Profiles` 范围。
- `NetworkList-NewNetworks.reg`：存在该键时，Restore 实际导入和校验的 `NewNetworks` 范围。
- `diagnostic.json` / `manifest.json`：保存诊断与备份元数据。

Restore 不再直接导入完整的 `NetworkList.reg`，以避免把 NetworkRepair 未管理的 Registry 子树一并覆盖。恢复失败时，工具会自动使用 Restore 前刚创建的安全备份，仅回滚上述 managed scopes。

可以恢复：

```bat
NetworkRepair.bat -Mode Restore -BackupPath "backups\\20261008_190429_297" -Yes
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
├─ tools/
│  ├─ Invoke-NRReadOnlyValidation.ps1
│  ├─ Export-NRSanitizedDiagnosticBundle.ps1
│  └─ New-NRReleasePackage.ps1
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

- [Windows 10 / 11 发布验证](docs/release-validation.md)
- [架构设计](docs/architecture.md)
- [路线图](docs/roadmap.md)
- [协作流程](docs/collaboration.md)
- [诊断代码](docs/diagnostic-codes.md)

## 项目路线

当前 `main` 已包含 1.0.0 的 Repair Planner、scoped Restore 快照校验、网络健康 / Profile 历史遗留双轨判定、只读快速 TUI 状态、脱敏诊断包与 Safe Repair 执行过程反馈。1.0.0 的核心发布阻塞项已收口，后续重点转向更精细的恢复点、服务刷新与用户体验能力。

## License

MIT
