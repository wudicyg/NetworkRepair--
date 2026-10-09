# NetMedic

安全、智能、可回滚的 Windows 网络配置诊断与修复工具。

> 当前稳定版本：**1.4.0**（见 [Releases](https://github.com/wudicyg/netmedic/releases)）
>
> 已经具备：图形界面（双击即用，无需记命令）、单文件免安装 exe、应用图标、更新检查、多级恢复点与按需服务刷新。
> 核心修复路径（Safe Repair / 历史编号 Profile 清理 / 备份与恢复 / 失败回滚）已在真实 Windows 10 + PowerShell 5.1 环境完成行为验证；
> **Windows 11 与更多语言/系统组合仍属于待验证的扩展兼容性项**，尚未作为发布待验证，如果你的系统是Windows 11可先行测试。

> **项目定位**：专门解决 Windows 网络名称持续出现「网络 2 / 网络 3 / 网络 4 / …」等历史 Network Profile 累积问题。  
> 在不破坏当前活动网络的前提下，先诊断、再备份、后清理并验证；同时提供 DNS、DHCP、网关、NCSI 等常见网络故障诊断与可回滚修复能力。

当前 `main` 分支版本：**1.4.0**

NetMedic 的目标不是“暴力清理注册表”，而是：

**先诊断 → 先备份 → 再修改 → 最后验证 → 失败回滚。**

## 项目定位

NetMedic 的核心任务不是“重置整个网络”，而是解决 Windows 长期使用后不断累积的编号网络 Profile，例如 `网络 2`、`网络 3`、`网络 4`、`Network 2` 等历史遗留项。

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
- Restore 只导入 NetMedic 管理的 `Profiles` / `NewNetworks` 范围，完成 scoped 快照校验；失败自动回到恢复前安全备份
- 网络健康与 Profile 历史遗留分离判断：网络健康时仍会识别并处理 `网络 2/3/4...` 历史 Profile
- 多级恢复点：备份按 `Manual` / `PreRepair` / `PreRestore` 分级，可列举、按序号恢复、固定保护，并按保留额度显式清理
- 按需服务刷新：仅在 `NetworkList` 范围真实改动后，按依赖顺序刷新 `NlaSvc` / `netprofm`，有界等待服务与 Network List Manager COM 恢复可用，并把刷新结果回传到修复、恢复与重命名结果
- 交互式菜单进入时提供只读快速状态概览，不触发 NCSI 主动探测；Repair 前仍执行完整重新诊断
- 图形界面（WinForms）：五张状态卡 + 一键操作按钮 + 带颜色的运行日志；修复前展示计划并要求确认
- 更新检查：命令行 `-Mode CheckUpdate` 与界面「检查更新」按钮；只检查与告知，不自动下载或替换自身
- 窗口化单文件主程序：双击直接进界面，无控制台窗口；控制台菜单与命令行参数仍通过 `备用启动` 与脚本可用
- 应用图标：`assets\NetMedic.ico` 嵌入 exe，窗口、任务栏与资源管理器统一显示
- 一键脱敏诊断包：只保留排障所需的非敏感摘要，排除机器名、MAC 地址、IP 地址、NetworkId、注册表路径与凭据（GUI「导出诊断报告」按钮直接产出这种）

## 快速开始

### 普通用户（推荐）

从 [Releases](https://github.com/wudicyg/netmedic/releases) 下载后**双击程序即可**：单文件封装、免安装，不需要在多个文件之间挑选。

- **`NetMedic-<版本>-Portable.exe`**：主程序本身，下载后直接双击，不用解压。
- **`NetMedic_<版本>_Windows.zip`**：完整发布包，解压后双击里面的 `网络医生.exe`（同一个程序）。
- 打开后是**图形界面**：顶部五张状态卡 + 一键操作按钮，点修复前会先展示本次修复计划并要求确认。
- 首次运行会弹出「用户账户控制」，选择「是」——本工具需要管理员权限才能读写网络配置。
- 若 exe 被安全软件拦截，改用 `备用启动\启动-网络医生.bat`（打开的是控制台菜单版），功能完全相同。
- 完整操作说明见 [使用说明.md](使用说明.md)。

> 发布页附件名使用 ASCII：GitHub 会剥掉附件名中的中文字符，因此中文名称以附件标签展示，包内入口仍是中文名。

### 从源码运行

双击：

```text
NetworkRepair.bat
```

命令行：

```bat
NetworkRepair.bat -Mode Gui
NetworkRepair.bat -Mode Scan
NetworkRepair.bat -Mode Repair
NetworkRepair.bat -Mode DeepRepair
NetworkRepair.bat -Mode Backup
NetworkRepair.bat -Mode Report
NetworkRepair.bat -Mode Rename -NetworkId "{GUID}" -NewName "Office"
NetworkRepair.bat -Mode CheckUpdate
NetworkRepair.bat -Mode CheckUpdate -Json
NetworkRepair.bat -Mode Version
```

> 全部可用模式（`-Mode` 的合法取值）：`Menu` / `Scan` / `Repair` / `DeepRepair` / `Backup` /
> `Restore` / `RestorePoints` / `Prune` / `Report` / `Rename` / `Gui` / `GuiSmoke` / `CheckUpdate` / `Version`。
> 其中 `Gui` 是打包后的默认模式；`GuiSmoke` 是无界面自检（供 CI 使用）；`Version` 只打印版本号。

JSON：

```bat
NetworkRepair.bat -Mode Scan -Json
```

导出脱敏诊断包（只读，不包含机器名、MAC、IP、NetworkId 或注册表备份）：

```bat
powershell.exe -ExecutionPolicy Bypass -File .\tools\Export-NRSanitizedDiagnosticBundle.ps1
```

> `-Mode Report` 产出的是**完整**诊断报告（含 MAC 地址、IP 地址与 NetworkId），命令会打印敏感数据
> 警告，公开分享前请改用上面的脱敏诊断包。图形界面的「导出诊断报告」按钮产出的就是脱敏包。

构建发布包（开发者/维护者）：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\New-NRReleasePackage.ps1
```

发布包由带 `v` 前缀的版本 Tag 触发 GitHub Actions 自动构建，产出 `NetMedic_<版本>_Windows.zip`、
`NetMedic-<版本>-Portable.exe` 以及各自同名的 `.sha256` 校验文件，并为发布页附件写入中文标签。
发布 Tag 必须与 `NetworkRepair.ps1` 中的版本完全一致。

跳过 Internet/DNS 测试：

```bat
NetworkRepair.bat -Mode Scan -SkipConnectivityTest
```


## 发布流程

GitHub Release 不会因为合并到 `main` 自动产生；只有推送与 `NetworkRepair.ps1` 里的 `$Script:AppVersion` **完全一致**的 Tag 后，Release 工作流才会创建发行版。版本号只在那一处硬编码，请以 [Releases](https://github.com/wudicyg/netmedic/releases) 与 [CHANGELOG.md](CHANGELOG.md) 为准。

发版步骤：

```powershell
# 1) 在分支上把 NetworkRepair.ps1 的版本号提升到目标版本，
#    并把 CHANGELOG.md 的 Unreleased 段落定稿为 ## [<版本>] - <日期>
# 2) 走分支 → PR → CI 通过 → 合并到 main
# 3) 推送与版本号一致的 Tag
git tag v<版本>
git push origin v<版本>
```

发布工作流会依次：校验 Tag 与应用版本一致 → 跑 Pester → 构建发布包（窗口化单文件 exe + 完整 zip + SHA-256）→ **用 CHANGELOG 对应段落生成发布正文**（含"该下载哪个文件"的说明）→ 创建 Release → 写入附件的中文标签。

> 发布正文取自 `CHANGELOG.md`：如果目标版本没有对应段落，流水线会直接失败——这样"工具发新版、文档没跟上"不会再发生。

更完整的门禁由 CI 工作流负责：Windows PowerShell 5.1 与 PowerShell 7 双引擎的语法解析与 Pester、
发布包内容与 SHA-256 校验、单文件入口真实运行、图形版 exe 的启动自检，以及一次真实网络的更新检查。

行为的实机证据以 Windows 10 核心场景为主；Windows 11 与更多环境组合属于后续扩展验证。
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

Restore 不再直接导入完整的 `NetworkList.reg`，以避免把 NetMedic 未管理的 Registry 子树一并覆盖。恢复失败时，工具会自动使用 Restore 前刚创建的安全备份，仅回滚上述 managed scopes。

### 恢复点等级与保留

`manifest.json` 记录每个恢复点的等级：

- `Manual`：菜单元 [4] 或 `-Mode Backup` 手动创建。
- `PreRepair`：修复前自动创建的安全点。
- `PreRestore`：恢复前自动创建的安全点，保证任何一次 Restore 都还能再回滚。
- 旧版备份没有等级字段时按 `Manual` 处理；未知等级按保守策略保留，不参与清理。

安全性：安全点（`PreRepair` / `PreRestore`）享有比普通恢复点更高的保留下限，已固定（`Pinned`）的恢复点永不参与清理；清理只允许删除 `backups\` 的直接子目录。

### 恢复与恢复点管理

列出恢复点（按时间新→旧编号）：

```bat
NetworkRepair.bat -Mode RestorePoints
```

按序号恢复，或按路径恢复（兼容旧用法）：

```bat
NetworkRepair.bat -Mode Restore -RestorePointIndex 1 -Yes
NetworkRepair.bat -Mode Restore -BackupPath "backups\20261008_190429_297" -Yes
```

清理超出保留额度的恢复点（先展示计划，确认后才删除）：

```bat
NetworkRepair.bat -Mode Prune
```

交互式菜单 [5] 会先列出可选恢复点，然后可选择 `R` 按序号恢复、`P` 清理、`F` 固定/取消固定，也可以直接输入备份目录或 `.reg` 路径。

## 日志

运行日志位于：

```text
logs/
```

默认不会写入 Wi-Fi 密码等凭据。

## 项目结构

```text
NetMedic/
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
│  ├─ RestorePoints.ps1
│  ├─ Services.ps1
│  ├─ Repair.ps1
│  ├─ Validation.ps1
│  ├─ Update.ps1
│  └─ Gui.ps1
├─ tests/
│  └─ NetworkRepair.Tests.ps1
├─ tools/
│  ├─ Invoke-NRReadOnlyValidation.ps1
│  ├─ Export-NRSanitizedDiagnosticBundle.ps1
│  ├─ New-NRSingleFileDistribution.ps1
│  ├─ New-NRIcon.ps1
│  ├─ New-NRReleasePackage.ps1
│  ├─ Get-NRReleaseNotes.ps1
│  ├─ Test-NRReleasePackage.ps1
│  └─ Set-NRReleaseAssetLabels.ps1
├─ assets/
│  └─ NetMedic.ico
├─ .github/
│  ├─ workflows/                 ← ci.yml / release.yml
│  ├─ ISSUE_TEMPLATE/
│  └─ PULL_REQUEST_TEMPLATE.md
├─ docs/
├─ backups/                      ← 运行期自动创建（仓库内仅 .gitkeep）
├─ logs/                         ← 运行期自动创建（仓库内仅 .gitkeep）
├─ reports/                      ← 运行期自动创建，存放导出的诊断报告
├─ README.md
├─ 使用说明.md
├─ LICENSE
├─ CHANGELOG.md
├─ CONTRIBUTING.md
├─ CODE_OF_CONDUCT.md
├─ SECURITY.md
└─ .gitignore
```

发布包面向普通用户的布局（发布页下载的 zip 解压后）：

```text
NetMedic_<版本>_Windows/
├─ 网络医生.exe              ← 双击这个即可
├─ 使用说明.md                  ← 中文快速上手
├─ 备用启动/
│  └─ 启动-网络医生.bat      ← exe 被安全软件拦截时使用
├─ NetworkRepair.single.ps1     ← 与 exe 内容相同的单文件脚本（便于审计）
├─ RELEASE-MANIFEST.txt         ← 构建产物清单（版本、生成时间、入口、提权方式）
├─ assets/NetMedic.ico          ← 程序图标（脚本方式运行时窗口图标从这里取）
├─ NetworkRepair.ps1 + src/     ← 开发用源码入口与模块
├─ tools/  docs/                ← 维护工具与设计文档
└─ README.md / CHANGELOG.md / LICENSE / ...
```

发布页还会单独提供便携版 exe，可直接下载、无需解压。注意 GitHub 会剥掉附件名里的非 ASCII 字符，
因此发布页上的文件名是 `NetMedic-<版本>-Portable.exe` 这样的英文名，中文名称显示在附件说明（label）上。

## 系统要求

- Windows 10 / Windows 11
- Windows PowerShell 5.1
- 管理员权限

NetMedic 使用 Windows `NetConnection` 模块获取 Connection Profile，并以 Network List Manager 所提供的网络信息模型为设计依据。

## 开发文档

- [Windows 10 / 11 发布验证](docs/release-validation.md)
- [架构设计](docs/architecture.md)
- [路线图](docs/roadmap.md)
- [协作流程](docs/collaboration.md)
- [诊断代码](docs/diagnostic-codes.md)

## 项目路线

`1.4.0` 起，普通用户拿到的是**带图形界面的单文件程序**：双击 `网络医生.exe` 即可，顶部状态卡看结论、一键按钮做修复、修改前自动备份并可回滚；程序自己会提示有没有新版本。

已完成：Safe Repair 与历史编号 Profile 清理、Repair Planner 与执行计划确认、scoped Restore 快照校验、网络健康 / Profile 历史遗留双轨判定、多级恢复点（分级 + 固定 + 显式清理）、按需服务刷新、脱敏诊断包、单文件分发与中文入口、图形界面、应用图标、更新检查。

后续重点（见 [路线图](docs/roadmap.md)）：**回归测试矩阵**（把已知故障场景固化为用例）与 **Windows 11 / 更多环境扩展验证**。

## License

MIT
