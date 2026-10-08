# 1.0.0 Release Validation

NetworkRepair 的 CI 负责脚本语法、Pester 与发布包回归；1.0.0 的核心行为验收以 Windows 10 PowerShell 5.1 实机结果为主要依据。Windows 11、更多 Windows Build 与语言环境作为后续扩展兼容性验证，不阻塞 1.0.0。

## 只读证据采集

在待测机器上运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -OutputPath .\validation\machine.json
```

跳过 Internet/NCSI 主动探测：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -SkipConnectivityTest -OutputPath .\validation\machine.json
```

该工具只读取系统状态，不执行 Repair、Deep Repair、Rename、Restore、服务重启或注册表写入。输出会省略 MAC 地址等与验收无关的信息。

## 核心验证矩阵

| 场景 | 期望 |
| --- | --- |
| 正常 Internet，且无编号历史 Profile | `NetworkHealth=Healthy`，`RepairRecommendation=NoAction`，不进入修改路径 |
| 正常 Internet，存在非活动 `网络 2/3/4` 或 `Network 2/3/4` | `NetworkHealth=Healthy`，仍识别为历史 Profile，并生成清理计划 |
| 正常 Internet，但编号 Profile 为当前活动连接 | 不允许自动删除 |
| 正常 Internet，但编号 Profile 为 Managed | 不允许自动删除 |
| Windows 10 + PowerShell 5.1 | 读取与 Safe Repair 回归通过 |
| Windows 11 + PowerShell 5.1 | 后续扩展验证，不阻塞 1.0.0 |
| DHCP IPv4 | 修复前后 IPv4、默认网关、DNS 正常 |
| 静态 IPv4 | 修复前后 IPv4、默认网关、DNS 保持 |
| Deep Repair | 只验证 `NewNetworks` 范围，不触碰 Signatures 无差别清理 |
| Rename | 显式 NetworkId 修改后名称与原意一致，失败可回滚 |
| Restore | 只恢复 NetworkRepair 管理的 `Profiles` / `NewNetworks`；恢复后各 scoped 快照匹配；失败时仅回滚到 Restore 前安全备份 |
| 中文/英文系统 | 当前以中文 Windows 10 的 `网络 N` 实机验证为主要证据；英文环境后续扩展验证 |

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

先运行只读证据采集器，保存 `machine.json`。

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

## 1.0.0 发布验收结论

当前 1.0.0 的核心目标是安全识别并清理非活动、非 Managed 的 `网络 N` / `Network N` 历史 Profile。该路径已经在真实 Windows 10 / PowerShell 5.1 环境完成实际运行验证。Windows 11 与更多环境组合继续保留测试入口，但不再作为 1.0.0 的发布阻塞项。
