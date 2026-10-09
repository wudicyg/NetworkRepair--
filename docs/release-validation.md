# Windows 10 Release Validation

NetMedic 的 CI 负责脚本语法、Pester、单文件 EXE 构建与发布包回归。维护者确认：Windows 10 实机验证矩阵已通过，所有已发布脚本版本与封装单文件 EXE（截至 `v1.4.0`）均已在真实 Windows 10 环境测试通过。Windows 11 当前没有可用实机，故暂缓适配与矩阵测试；不把 Windows 11 当作当前支持承诺，也不作为本阶段发布阻塞项。

## 只读证据采集

在待测机器上运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -OutputPath .\validation\machine.json
```

跳过 Internet/NCSI 主动探测：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -SkipConnectivityTest -OutputPath .\validation\machine.json
```

该工具只读取系统状态，不执行 Repair、Deep Repair、Rename、Restore、服务重启或注册表写入。默认输出为脱敏摘要，会省略计算机名、适配器/接口名、具体 Profile 名、MAC、IP、NetworkId、注册表路径及原始网络标识。

如确有需要在私下排障时查看完整字段，可显式添加 `-IncludeSensitiveDetails`。此模式会导出机器名、Profile/接口名、NetworkId、注册表路径和 IP 配置等敏感内容，只应保存在本机安全位置，绝不能公开上传。报告/诊断 ZIP 的脱敏规则见[隐私说明](privacy.md)。

## 核心验证矩阵

| 场景 | 当前结论 |
| --- | --- |
| Windows 10 + PowerShell 5.1 | ✅ 实机验证通过（维护者确认） |
| 已发布脚本与单文件 EXE（截至 `v1.4.0`） | ✅ 全部已在真实 Windows 10 环境测试通过（维护者确认） |
| 正常 Internet、无编号历史 Profile | ✅ 验证为 `Healthy` + `NoAction`，不进入修改路径 |
| 正常 Internet + 非活动 `网络 2/3/4` / `Network 2/3/4` | ✅ 识别历史项并生成安全清理计划 |
| 活动或 Managed 编号 Profile | ✅ 受保护，不允许自动删除 |
| DHCP IPv4 / 静态 IPv4 | ✅ Windows 10 验证矩阵通过 |
| Safe Repair / Deep Repair | ✅ Windows 10 验证矩阵通过；Deep Repair 限定于允许的 `NewNetworks` 范围 |
| Rename / Backup / Restore / 失败回滚 | ✅ Windows 10 验证矩阵通过 |
| Windows 11 | ⏸ 暂缓；当前没有 Windows 11 实机，未声明已验证或兼容，不阻塞当前 Windows 10 发布 |
| 英文 Windows / 更多 Windows Build | ⏸ 暂缓扩展测试；不与已通过的 Windows 10 矩阵混为一谈 |

### Restore 证据要求

Restore 不应以完整 `NetworkList.reg` 导入成功作为验收标准。测试记录至少应包含：

- Restore 前创建的安全备份目录。
- `NetworkList-Profiles.reg` 和（存在时）`NetworkList-NewNetworks.reg`。
- Restore 过程结果及退出状态。
- Restore 后各 managed scope 的快照校验结果。
- 如校验失败，自动回滚及回滚后的再次校验结果。

完整 `NetworkList.reg` 作为基线快照保留，用于审计和故障排查，不作为默认 Restore 导入文件。

## 推荐测试顺序

### 1. 基线

先运行只读证据采集器，保存默认脱敏的 `machine.json`。如需要原始标识信息，仅在本机使用 `-IncludeSensitiveDetails`，不得把该文件公开上传。

记录 Windows Build、PowerShell、网卡介质、当前连接、NetworkHealth、编号 Profile 数量。

### 2. 健康网络无历史 Profile

验证结果必须是：

```text
NetworkHealth = Healthy
ProfileHygieneStatus = Clean
RepairRecommendation = NoAction
```

随后运行：

```powershell
.\NetworkRepair.bat -Mode Repair
```

观察脚本只能诊断并显示“无需修复”，不得创建修改前备份，不得删除注册表。

### 3. 健康网络 + 历史编号 Profile

在可回滚的测试环境中准备至少：

```text
网络 2
网络 3
Network 4
```

并确保这些 Profile 不是当前活动连接、不是 Managed。

执行：

```powershell
.\NetworkRepair.bat -Mode Repair
```

在确认提示前检查显示的修复计划，应为：

```text
NetworkHealth = Healthy
ProfileHygieneStatus = HistoricalProfilesFound
RepairRecommendation = CleanHistoricalProfiles
```

并看到 3 个 `DeleteProfile` 动作；确认后再执行实际修复。

### 4. 保护性回归

将其中一个编号 Profile 设为当前活动连接，或让它成为 Managed Profile。

再次执行 Repair，在确认前检查保护结果。

期望该对象进入：

```text
ProtectedNumberedProfilesPresent
```

且 `DeleteProfileCount` 不包含受保护对象。

## 证据留存

每台机器至少保留：

- `machine.json`
- Safe Repair 前后诊断结果
- 如执行 Restore/Rename，再保存对应日志、备份目录和 scoped 验证结果
- Windows 版本、PowerShell、网卡介质、测试日期

不要把 Wi-Fi 密码、VPN 凭据或其他秘密数据上传到 Issue。

## 当前发布验收结论（最新正式版 v1.4.0）

维护者确认：Windows 10 + PowerShell 5.1 验证矩阵已通过，所有已发布脚本版本和单文件 EXE（截至 `v1.4.0`）均已在真实 Windows 10 环境完成测试。CI 同时覆盖 PowerShell 5.1、PowerShell 7、Pester、单文件 EXE 启动自检与发布包校验。

Windows 11 当前没有可用实机，因此不宣称已经测试、适配或兼容；本阶段不继续投入 Windows 11 适配/矩阵，待获得对应测试环境后再单独规划。
