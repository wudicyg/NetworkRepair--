# 发布验证（Release Validation）

NetMedic 的 CI 负责脚本语法（Windows PowerShell 5.1 与 PowerShell 7 双引擎）、Pester、发布包构建与布局
校验、单文件入口真实运行、图形版 exe 的 `-Mode GuiSmoke` 启动自检，以及一次真实网络的更新检查；
发布工作流另外用 CHANGELOG 生成发布正文并写入中文附件标签。

各版本的**核心行为验收**以 Windows 10 / PowerShell 5.1 实机结果为主要依据。Windows 11、更多 Windows
Build 与语言环境作为后续扩展兼容性验证，不阻塞当前版本发布。

## 当前版本（1.5.1）验收范围

除下面的通用矩阵外，1.1.0 起新增的能力也需要在实机上过一遍：

| 能力 | 验收方式 | 期望 |
| --- | --- | --- |
| 单文件主程序 | 双击 `网络医生.exe` | 弹出 UAC 后进入图形界面；不出现控制台窗口；任务栏与资源管理器显示应用图标 |
| 图形界面 | 观察首屏 | 五张状态卡有值；「重新诊断」可刷新；修复按钮在忙碌时禁用 |
| 修复前计划确认 | 点「安全修复」 | 先弹出本次修复计划（要删除哪些 Profile、是否刷新 NewNetworks），确认后才执行 |
| 恢复点管理 | 点「恢复点管理」 | 列出序号/时间/等级/状态，可恢复、固定/取消固定、清理超出额度 |
| 界面自检 | `网络医生.exe -Mode GuiSmoke` | 进程自行退出、退出码 0（无模态弹窗阻塞） |
| 更新检查 | 界面「检查更新」或 `-Mode CheckUpdate` | 报出最新版本；**不下载、不替换自身**；断网时给出提示且不影响其它功能 |
| 脱敏导出 | 点「导出诊断报告」 | 产出 zip，内容不含机器名、MAC、IP、NetworkId、注册表路径 |
| 提权清单 | 资源管理器属性或十六进制查看 | exe 内嵌 `requireAdministrator` |

## 只读证据采集

在待测机器上运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -OutputPath .\validation\machine.json
```

跳过 Internet/NCSI 主动探测：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -SkipConnectivityTest -OutputPath .\validation\machine.json
```

该工具只读取系统状态，不执行 Repair、Deep Repair、Rename、Restore、服务重启或注册表写入。输出会省略
MAC 地址；但**仍包含计算机名、连接名与网卡描述**，需要公开发布时请改用脱敏诊断包：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Export-NRSanitizedDiagnosticBundle.ps1
```

## 核心验证矩阵

| 场景 | 期望 |
| --- | --- |
| 正常 Internet，且无编号历史 Profile | `NetworkHealth=Healthy`，`RepairRecommendation=NoAction`，不进入修改路径 |
| 正常 Internet，存在非活动 `网络 2/3/4` 或 `Network 2/3/4` | `NetworkHealth=Healthy`，仍识别为历史 Profile，并生成清理计划 |
| 正常 Internet，但编号 Profile 为当前活动连接 | 不允许自动删除 |
| 正常 Internet，但编号 Profile 为 Managed | 不允许自动删除 |
| Windows 10 + PowerShell 5.1 | 读取与 Safe Repair 回归通过 |
| Windows 11 + PowerShell 5.1 | 扩展验证项，尚未作为发布阻塞项 |
| DHCP IPv4 | 修复前后 IPv4、默认网关、DNS 正常 |
| 静态 IPv4 | 修复前后 IPv4、默认网关、DNS 保持 |
| Deep Repair | 只验证 `NewNetworks` 范围，不触碰 Signatures 无差别清理 |
| Rename | 显式 NetworkId 修改后名称与原意一致，失败可回滚 |
| Restore | 只恢复 NetMedic 管理的 `Profiles` / `NewNetworks`；恢复后各 scoped 快照匹配；失败时仅回滚到 Restore 前安全备份 |
| 发布产物一致性 | 便携 exe 与 zip 内 `网络医生.exe` 的 SHA-256 与随附 `.sha256` 文件一致；包内含 `assets\NetMedic.ico` 与 `RELEASE-MANIFEST.txt` |
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

随后执行修复（**注意入口随场景不同**）：

```powershell
# 源码仓库内：
.\NetworkRepair.bat -Mode Repair

# 等价于（任意场景都可用的脚本方式）：
powershell.exe -ExecutionPolicy Bypass -File .\NetworkRepair.ps1 -Mode Repair

# 验证发布包时（解压后）：
.\网络医生.exe                       # 图形界面，手动点「安全修复」
.\备用启动\启动-网络医生.bat -Mode Repair   # 控制台界面
```

观察只能诊断并显示"无需修复"，不得创建修改前备份，不得删除注册表。

### 3. 健康网络 + 历史编号 Profile

在可回滚的测试环境中准备至少：

```text
网络 2
网络 3
Network 4
```

并确保这些 Profile 不是当前活动连接、不是 Managed。

执行修复（命令同上），在确认提示前检查显示的修复计划，应为：

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

### 5. 发布产物与界面回归（1.1.0 起）

1. 从发布页下载便携 exe 与 zip，分别核对随附的 `.sha256`。
2. 解压 zip，确认包内中文入口 `网络医生.exe`、`备用启动\启动-网络医生.bat`、`assets\NetMedic.ico`、
   `RELEASE-MANIFEST.txt` 均在，且**不存在** `NetworkRepair.bat`（它只在源码仓库里）。
3. 双击 `网络医生.exe`：应进入图形界面，无控制台窗口。
4. `网络医生.exe -Mode GuiSmoke`：退出码应为 0。
5. 点「检查更新」：应报出最新版本且不下载任何东西。
6. 点「导出诊断报告」：产出的 zip 中不应出现 MAC 地址、IP 地址或 NetworkId。

## 证据留存

每台机器至少保留：

- `machine.json`
- Safe Repair 前后诊断结果
- 如执行 Restore/Rename，再保存对应日志、备份目录和 scoped 验证结果
- 发布产物校验：便携 exe 与 zip 的 SHA-256 及其与随附校验文件的一致性
- Windows 版本、PowerShell、网卡介质、测试日期

不要把 Wi-Fi 密码、VPN 凭据或其他秘密数据上传到 Issue。含机器名 / MAC / IP / NetworkId 的原始
`machine.json` 与完整诊断报告同样不要公开上传。

## 1.0.0 历史验收结论（保留）

1.0.0 的核心目标是安全识别并清理非活动、非 Managed 的 `网络 N` / `Network N` 历史 Profile。该路径
已经在真实 Windows 10 / PowerShell 5.1 环境完成实际运行验证。Windows 11 与更多环境组合继续保留测试
入口，但不再作为发布阻塞项。
