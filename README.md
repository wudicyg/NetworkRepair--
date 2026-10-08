# NetworkRepair

安全、智能、可回滚的 Windows 网络配置诊断与修复工具。

> 当前开发版本：**0.4.0-dev**
>
> `0.4.0-dev` 已完成核心 Safe Repair 实机验证；正式稳定版仍以 Windows 10/11 多版本矩阵与发布验收为准。

> **项目定位**：专门解决 Windows 网络名称持续出现「网络 2 / 网络 3 / 网络 4 / …」等历史 Network Profile 累积问题。  
> 在不破坏当前活动网络的前提下，先诊断、再备份、后清理并验证；同时提供 DNS、DHCP、网关、NCSI 等常见网络故障诊断与可回滚修复能力。

当前主分支：**0.4.0-dev**

NetworkRepair 的目标不是“暴力清理注册表”，而是：

**先诊断 → 先备份 → 再修改 → 最后验证 → 失败回滚。**

## 项目定位

NetworkRepair 的核心任务不是“重置整个网络”，而是解决 Windows 长期使用后不断累积的编号网络 Profile，例如 `网络 2`、`网络 3`、`网络 4`、`Network 2` 等历史遗留项。

网络连通性诊断与修复属于配套能力：当网络本身正常时，工具不会为了测试而盲目修改系统；当网络正常但存在符合安全规则的历史编号 Profile 时，仍会独立识别并提供清理计划。

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
- 只读发布验收证据采集器
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

导出脱敏诊断包（只读，不包含机器名、MAC、IP、NetworkId 或注册表备份）：

```bat
powershell.exe -ExecutionPolicy Bypass -File .\tools\Export-NRSanitizedDiagnosticBundle.ps1
```

构建发布包（开发者/维护者）：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\New-NRReleasePackage.ps1
```

发布包由带 `v` 前缀的版本 Tag 触发 GitHub Actions 自动构建，并生成 ZIP 与 SHA-256 校验文件。发布 Tag 必须与 `NetworkRepair.ps1` 中的版本完全一致。

跳过 Internet/DNS 测试：

```bat
NetworkRepair.bat -Mode Scan -SkipConnectivityTest
```


## 发布流程

GitHub Release 不会因为合并到 `main` 自动产生；只有推送与 `NetworkRepair.ps1` 版本完全一致的 Tag 后，Release 工作流才会创建发行版。

当前开发版为：

```text
0.4.0-dev
```

开发/预发布版本可使用：

```powershell
git tag v0.4.0-dev
git push origin v0.4.0-dev
```

带 `-` 的版本会被 GitHub Actions 发布为 **Prerelease**。正式稳定版则应先把脚本版本更新为不带预发布后缀的版本，例如：

```text
0.4.0
```

然后：

```powershell
git tag v0.4.0
git push origin v0.4.0
```

Release 工作流会在发布前执行 PowerShell 5.1 / PowerShell 7 所需的 Pester 测试、构建 Windows ZIP、生成 SHA-256 校验文件，并校验 Tag 与应用版本是否完全一致。正式版发布前仍应完成 [Windows 10 / 11 发布验证](docs/release-validation.md) 中的实机矩阵。
## 安全模型

### Safe Repair

默认只自动处理：

1. 名称匹配 `网络 N` 或 `Network N`；
2. 不是当前活动连接；
3. 不属于 Managed 配置。

### Deep Repair

在 Safe Repair 基础上刷新 `NewNetworks`。当前开发版 **不会**无条件删除 `Signatures\Managed` / `Signatures\Unmanaged`，因为这些签名数据可能参与网络识别，尤其在企业环境中不适合默认破坏。

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
- [诊断代码](docs/diagnostic-codes.md)

## 项目路线

当前 `main` 已包含 v0.4 的 Repair Planner、Restore 快照校验、网络健康 / Profile 历史遗留双轨判定、只读发布验收证据采集，以及 Safe Repair 执行过程反馈。正式稳定版仍需完成 Windows 10 / 11 多版本实机矩阵、更多语言环境与发布包验证。后续重点是 TUI 增强、脱敏诊断包和多级恢复点。

## License

MIT
