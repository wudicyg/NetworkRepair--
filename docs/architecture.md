# Architecture

```text
BAT launcher
    ↓
NetworkRepair.ps1
    ↓
Diagnostics
    ├─ Network Health Assessment
    └─ Profile Hygiene Assessment
    ↓
Repair Decision
    ↓
Repair Planner
    ├─ Safe Repair → eligible profile deletions
    └─ Deep Repair → explicit NewNetworks refresh
    ↓
Backup
    ↓
Repair / Restore
    ↓
Validation
    ├─ Repair validation
    └─ Restore snapshot verification
    ↓
Rollback on failure
```

## Safety boundary

注册表在诊断阶段只读。自动删除仍被 `RemediationAllowed` 安全门槛限制：候选必须通过编号网络名称规则、非当前活动连接、非 Managed 等条件。活动 Profile 与 Managed Profile 永远不能进入自动删除路径。

所有真正的修改都先创建备份，再执行修改，最后验证。修复或恢复验证失败时优先回到修改前的安全状态。

## Repair Planner

v0.4.x 将“要做什么”和“怎么执行”分开。Repair Planner 负责把诊断候选转换成显式操作计划，修复前的确认提示与实际执行共用同一计划，因此预览结果和实际执行路径保持一致。

Safe Repair 的删除动作只能来自 `RemediationAllowed` 候选；Deep Repair 额外提供明确的 `NetworkList\\NewNetworks` 刷新动作，不会因此扩大到 `Signatures\\Managed` / `Signatures\\Unmanaged` 的无差别清理。

## Restore verification

Restore 在导入目标 `.reg` 前创建当前状态的安全备份。导入后会重新导出当前 `NetworkList`，将其与所选备份进行规范化比较；只有快照匹配后才认为恢复成功。

如果恢复后的快照校验失败，会导入恢复前的安全备份，并再次验证安全备份是否已经恢复。若回滚自身也失败，会明确返回回滚失败状态和安全备份路径。

## Restore points

所有修改前创建的备份都是恢复点，`src/RestorePoints.ps1` 把它们组织为分级、可列举、可安全轮转的集合：

- **等级**：`Manual`（菜单/CLI 手动创建）、`PreRepair`（修复前自动创建）、`PreRestore`（恢复前自动创建，保证任何 Restore 都还能再回滚）。旧版 manifest 没有等级字段时按 `Manual` 处理；未知等级不做猜测，按保守策略保留。
- **完整性**：缺少 `NetworkList.reg` 或 `NetworkList-Profiles.reg` 的恢复点标记为 `Incomplete`，manifest 无法解析标记为 `Unreadable`；完整性异常的恢复点不允许用于恢复。
- **保留策略**：每个等级保留最近 `KeepPerLevel`（默认 10）个；安全点至少保留 `KeepSafetyPerLevel`（默认 3）个；`Pinned` 恢复点永不参与清理。
- **清理边界**：清理只在显式确认后执行，并且只允许删除备份根目录的直接子目录，其余路径一律跳过并报告，防止 manifest 被篡改后越权删除。

## Service refresh

`NetworkList` 范围（`Profiles` / `NewNetworks`）发生真实改动后，`src/Services.ps1` 负责刷新 NlaSvc 与 netprofm：

- **按需刷新**：没有实际注册表改动时（例如健康网络的 NoAction 修复）跳过刷新，不再无条件重启网络服务。
- **依赖顺序**：netprofm 依赖 NlaSvc，停止顺序为 netprofm → NlaSvc，启动顺序相反；被 `-Force` 连带停止的清单外依赖服务会被记录，并在随后一并拉起。
- **有界验证**：不再使用固定 `Start-Sleep 2`，改为在超时上限内轮询服务状态，并以 Network List Manager COM 是否恢复可用作为就绪判据。
- **不扩大修改范围**：原本未运行或未安装的服务不会被主动启动，只如实记录。
- **结果回传**：刷新返回结构化结果（`Refreshed` / `NotRunning` / `Missing` / `Failed` / `Collateral` / `ComReady` / `Degraded`），修复、恢复与重命名都会把它带进各自的返回对象，降级时给出可见提示。

## Graphical interface

`src/Gui.ps1` 在既有能力之上加了一层 WinForms 界面，通过 `-Mode Gui` 进入；打包后的 exe 默认就是它。

- **不新增修改边界**：界面只调用既有函数。修复候选仍由 `RemediationAllowed` 等安全门槛决定，点击修复前仍弹出本次修复计划并要求确认，验证与自动回滚路径完全不变。
- **逻辑与界面分离**：状态卡文案（`Get-NRGuiStatusCards`）、修复计划摘要（`Get-NRGuiPlanSummary`）、按钮可用性（`Get-NRGuiActionAvailability`）都是纯函数，可在无界面环境下单测；窗口构建（`New-NRGuiForm`）与显示（`Show-NRGui`）分离，后者才真正进入消息循环。
- **程序集延迟加载**：只有构建窗口时才加载 `System.Windows.Forms` / `System.Drawing`，命令行与 CI 路径不受影响。
- **无控制台环境适配**：图形版 exe 没有控制台，界面自己渲染日志，并把 `$Json` 置为静默分支，避免向不存在的控制台写内容；启动阶段异常改用对话框呈现。
- **可验证性**：`-Mode GuiSmoke` 会构建完整窗口、核对关键控件与尺寸后释放，不接触系统状态也不需要管理员权限，CI 因此能真正验证界面代码可以构建。
- **窗口化打包**：分发脚本默认 `DefaultMode = 'Gui'`，编译时传入 `-noConsole -STA -DPIAware`；控制台 TUI 由备用启动器显式以 `-Mode Menu` 进入。
- **必须同时加 `-noOutput`**：ps2exe 在无控制台模式下会把脚本输出（`Write-Output` 与 `Write-Host` 都算）收集起来，用一个模态对话框显示，进程会一直等到用户点「确定」。实测不加该开关时，打包后的 exe 一有输出就弹窗并卡住；CI 因此用「带超时的等待 + 退出码」而不是无限等待来验证图形版启动。
- **应用图标**：`assets/NetMedic.ico` 由 `tools/New-NRIcon.ps1` 生成（可重复生成，仓库里不存手改的二进制）。exe 编译时通过 `-iconFile` 嵌入；窗口图标在打包运行时用 `Icon::ExtractAssociatedIcon` 取自自身进程映像，脚本方式运行时回退到包内 `assets\NetMedic.ico`。小尺寸用传统 DIB 条目、大尺寸用 PNG 条目压缩，兼顾兼容性与体积。

## Update check

`src/Update.ps1` 查询 GitHub 发布页的最新版本并与当前版本比较，不涉及本机任何配置。

- **只检查、只告知**：不自动下载、不自动替换自身。自替换需要提权、代码签名与失败回滚，属于新的风险面，与项目「先诊断、先备份、可回滚」的姿态不符；是否升级由用户自己决定。
- **可测的纯函数**：版本解析（`ConvertTo-NRVersionParts`）与比较（`Compare-NRVersion`）不碰网络。按主/次/修订号逐位数字比较（不是字符串比较，否则 `1.10.0` 会被判成比 `1.2.0` 旧），数字相同时带预发布后缀的一侧更旧；无法解析时返回空值而不是抛异常。
- **失败不致命**：`Get-NRLatestRelease` 把网络异常收敛成 `Success=$false` + `Error`，绝不向上抛。检查失败只记一条 WARN 日志。
- **不阻塞用户**：命令行 `-Mode CheckUpdate` 放在提权检查之前（只读检查不需要管理员权限），失败退出码 9、成功 0；界面里的启动检查只在诊断结果网络健康时进行，网络不通就跳过，因为本工具常被用来修网络。
- **隐私**：只读取 GitHub 公开的发布元数据，不上报任何本机数据。

## Diagnostic layers

- Connection Profile
- Network List Manager COM
- IP / DHCP / Gateway / DNS
- NCSI DNS / HTTP probe
- Explainable risk scoring
- Registry Profile GUID ↔ NetworkId correlation

The write boundary remains unchanged: only explicitly eligible non-active, non-managed candidates can enter Safe Repair.


## Health vs. Profile hygiene

NetMedic treats network connectivity health and Network List Profile hygiene as two independent dimensions.

A machine can be **Healthy** while still containing historical numbered Profiles such as `网络 2`, `网络 3`, or `Network 4`. In that case the report says the network is healthy but recommends historical Profile cleanup, and the Repair Planner may still generate safe deletion actions for inactive, non-Managed candidates.

Conversely, a healthy connection does not make an active or Managed numbered Profile eligible for deletion. Safety gates remain authoritative.

When there is no historical Profile cleanup candidate and the network is healthy, the repair decision is explicitly `NoAction`; the tool does not enter a destructive repair path merely because it was invoked for testing.

## Distribution packaging

`tools/New-NRSingleFileDistribution.ps1` 把入口脚本与 `src/` 下全部模块按点源顺序压平成单个脚本：压平后的脚本在语义上与逐文件点源一致，但不再依赖 `src/` 目录，因此可以直接编译成单文件 exe。

- **单文件 exe**：用 ps2exe 编译，默认嵌入 `requireAdministrator` 清单（构建后用字节搜索校验该标记确实存在）。exe 宿主中 `$MyInvocation.MyCommand` 没有 `Path` 属性，入口路径按「脚本路径 → `PSCommandPath` → 进程映像 → 应用程序域基目录」回退；提权逻辑再按宿主类型决定是重新运行入口脚本还是重启自身。
- **备用启动器**：`备用启动\启动-网络医生.bat` 内容为纯 ASCII（批处理对中文内容与代码页敏感，中文只出现在文件名上），指向同一份压平脚本。
- **发布包布局**：根目录只保留一个显眼入口 `网络医生.exe`，配套 `使用说明.md`；源码、文档与工具保持原有目录结构，供审计与二次开发。
- **zip 编码**：使用 `ZipFile::CreateFromDirectory` 并显式传入 UTF-8 条目名，避免中文文件名解压后变成乱码；`Compress-Archive` 不保证这一点。
