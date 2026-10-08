# Changelog

## Unreleased

### Added
- **图形化界面（GUI）**：新增 `src/Gui.ps1` 与 `-Mode Gui`。窗口顶部是五张状态卡（网络健康度 / 当前连接 / 可安全清理 / 恢复点 / 诊断完整性），中间是操作按钮（重新诊断、安全修复、深度修复、手动备份、恢复点管理、导出诊断报告、打开日志目录、关于），底部是带时间戳与颜色的运行日志。点击修复前仍会弹出本次修复计划并要求确认，安全门槛完全复用既有逻辑，**未新增任何修改边界**。
- **窗口化主程序**：打包后的 `网络修复工具.exe` 不再弹出黑色控制台窗口，双击直接进入图形界面。分发脚本的默认模式改为 `Gui`；控制台 TUI 由 `备用启动\启动-网络修复工具.bat` 显式以 `-Mode Menu` 进入，命令行参数照旧可用。
- 新增 `-Mode GuiSmoke`：无界面自检（构建完整窗口、核对关键控件与尺寸后释放），不接触系统状态，因此不需要管理员权限。CI 用它证明界面代码可以真正构建，而不只是能通过语法解析。
- **应用图标**：新增 `tools/New-NRIcon.ps1` 与 `assets/NetworkRepair.ico`（16/32/48/64/128/256 六个尺寸，小尺寸用传统 DIB 条目、大尺寸用 PNG 条目压缩，约 30 KB）。图标嵌入 exe（任务栏、资源管理器、标题栏都用它），窗口图标在打包运行时取自 exe 自身、脚本运行时回退到包内 `assets\`。

### Fixed
- 修正 `List[object]` 在 PowerShell 5.1 下被 `@()` 包装会抛「Argument types do not match / 参数类型不匹配」的隐患，并新增测试禁止该写法（该陷阱在仓库中已经出现两次）。
- **修复图形版 exe 弹出模态输出对话框的问题**：ps2exe 在无控制台模式下会把脚本输出（`Write-Output` 与 `Write-Host` 都算）收集起来用一个模态对话框显示，进程会一直等到用户点「确定」。图形版现在编译时加 `-noOutput`；同时把 CI 的图形版启动检查改成**带超时的等待**，将来若再出现弹窗阻塞会直接判定失败，而不是把 CI 挂死。

## [1.1.0] - 2026-10-08

### Added
- **多级恢复点**：备份现在带等级（`Manual` / `PreRepair` / `PreRestore`）与固定标记，新增 `src/RestorePoints.ps1` 提供恢复点列举、完整性检查、保留策略计算与显式确认后的清理；`Restore` 支持按恢复点序号恢复（`-RestorePointIndex`），新增 `-Mode RestorePoints` 与 `-Mode Prune`。安全点（PreRepair/PreRestore）与已固定恢复点享有更高保留下限，清理只允许删除备份根目录的直接子目录。
- **更精细的服务刷新策略**：新增 `src/Services.ps1`。刷新按实际影响范围决策（没有注册表改动时跳过，不再无条件重启网络服务）、按依赖顺序重启（停止 netprofm → NlaSvc，启动反向）、在有界超时内轮询服务状态，并以 Network List Manager COM 是否恢复可用作为就绪判据，替代原先的固定 `Start-Sleep 2`；被 `-Force` 连带停止的清单外依赖服务会先记录并随后一并拉起，原本未运行/未安装的服务不主动启动。刷新结果（`Refreshed` / `NotRunning` / `Missing` / `Failed` / `Collateral` / `ComReady` / `Degraded`）会回传到修复、恢复与重命名的返回对象，降级时给出可见提示。
- 新增 `Write-NRSafeLog`：没有日志文件上下文时（例如单元测试直接点源模块）静默跳过，避免日志写入失败打断主流程。
- **面向普通用户的单文件分发**：新增 `tools/New-NRSingleFileDistribution.ps1`，把入口脚本与 `src/` 下 11 个模块按点源顺序压平成单个脚本，并用 ps2exe 编译成单文件 `网络修复工具.exe`（默认嵌入 requireAdministrator 清单，并经字节校验确认），同时生成纯 ASCII 的备用启动器。发布包改为「一个显眼入口」布局：`网络修复工具.exe` + `使用说明.md` + `备用启动\启动-网络修复工具.bat`；zip 改用 ZipFile + UTF-8 条目名写入，中文文件名解压后不再乱码；Release 额外附带可直接下载的便携 exe 与其校验文件。
- 新增面向普通用户的中文说明 `使用说明.md`：第一句话就说明「双击哪个文件」。
- 发布页附件命名：GitHub 会**剥掉附件名里的非 ASCII 字符**（实测上传 `网络修复工具_1.0.0.exe` 会存成 `_1.0.0.exe`），因此附件名改用 ASCII 的 `NetworkRepair-<版本>-Portable.exe`，中文名称改由附件的 `label` 字段承载（新增 `tools/Set-NRReleaseAssetLabels.ps1`）。包**内**的用户可见入口仍然是中文名。

### Changed
- 网络重命名前的自动备份也使用 `PreRepair` 安全点等级，与修复、恢复路径保持一致，避免修改前的安全点被当作普通恢复点优先清理。
- 明确 Issues 与 Discussions 的分工：新增协作流程文档 `docs/collaboration.md`，Issue 模板页增加 Q&A / Ideas / 私密安全报告入口，`CONTRIBUTING.md` 补充分支命名与 PR 门禁。
- 发布包不再包含旧 ASCII 启动器 `NetworkRepair.bat`（仅保留在源码仓库中），避免普通用户在多个入口之间犹豫。

### Fixed
- 删除 `.github/pull_request_template.md`：它与 `.github/PULL_REQUEST_TEMPLATE.md` 仅大小写不同，在 Windows 上检出会产生文件冲突，且内容仍在引用 1.0.0 已移除的 Dry Run。
- **修复打包成 exe 后无法启动**：入口脚本原先用 `$MyInvocation.MyCommand.Path` 推导根目录，而 ps2exe 宿主没有该属性，在 `Set-StrictMode -Version Latest` 下会直接抛「找不到属性 Path」。现在按「脚本路径 → PSCommandPath → 进程映像 → 应用程序基目录」顺序回退，并记录宿主类型。
- 提权重启现在区分宿主：脚本宿主以 `-File` 重新运行入口脚本，已打包的 exe 则直接以管理员身份重启自身。
- 新增测试守住 `.ps1` 必须带 UTF-8 BOM 的约定：PowerShell 5.1 在中文区域会按 ANSI 解码没有 BOM 的脚本，中文注释里的多字节序列会被还原成引号或括号，导致脚本解析直接失败。

## [1.0.0] - 2026-10-08

### Release
- NetworkRepair 1.0.0 首个正式稳定版。
- 核心历史编号 Profile（网络 N / Network N）安全清理路径、scoped Backup/Restore、诊断、验证和自动回滚能力完成收口。
- 正式版移除开发/验收用途的独立 Dry Run 功能，交互式菜单收口为 7 项主要操作。
- Windows 10 / PowerShell 5.1 核心实机行为验证完成；Windows 11 与更多环境作为后续兼容性验证。

## 0.4.0 — 稳定版候选阶段（未单独发布）

### Release
- 完成核心 Safe Repair、历史编号 Profile 清理、scoped Backup/Restore、诊断与回滚路径，为 1.0.0 正式稳定版奠定基础。
- Windows 10 / PowerShell 5.1 完成核心实机行为验证；Windows 11 与更多环境作为后续扩展验证，不阻塞本版本发布。

## [0.4.0-dev]

### Added
- 独立修复决策计划层，统一修复决策与真实执行路径。
- Deep Repair 在无可删除 Profile 时仍可明确执行 `NewNetworks` 刷新。
- Restore 完成注册表快照校验；校验失败时自动回到恢复前安全备份并再次验证。
- 增加修复计划与注册表快照比较回归测试。
- 网络健康状态与 Profile 历史遗留独立判断；健康网络仍可生成历史 Profile 清理计划。
- 健康网络且无安全清理候选时明确返回 NoAction，不进入修改路径。
- 一键脱敏诊断包导出器，仅保留发布验收和故障排查所需的非敏感摘要。
- 标准发布包构建器与 Tag 驱动的 GitHub Release 自动化。
- 交互式菜单增加只读快速状态概览，区分当前网络健康度、可安全清理的历史编号 Profile 与受保护编号 Profile。

### Removed
- 正式版移除仅用于开发/验收的独立 Dry Run 菜单与 `-Mode DryRun` 入口；Repair 仍会在确认前展示本次实际修复计划。

### Changed
- 人类可读诊断报告现在会明确显示非致命诊断阶段的降级提示，并继续允许完成其余可用诊断。
- 脱敏诊断包工具从入口脚本自动读取应用版本，避免开发版本号漂移。
- 开发版本 Tag（例如 `v0.4.0-dev`）由 Release 工作流自动标记为 Prerelease，并在创建 Release 前验证 Tag。
- Release 发布流程补充文档，明确合并 `main` 不会自动创建 GitHub Release。
- CI 增加 Release 工作流关键安全开关的静态回归检查。
- 备份与发布验收文档现在明确区分完整 `NetworkList.reg` 基线快照与 Restore 实际导入的 `Profiles` / `NewNetworks` managed scopes。
- 1.0.0 稳定版收口发布门槛：核心 Windows 10 实机行为作为主要验收依据，Windows 11/更多环境转为后续扩展验证。

### Fixed
- Deep Repair 在网络健康且没有可安全清理 Profile 时不再生成破坏性 `NewNetworks` 刷新动作。
- 注册表 Profile 扫描容忍缺失的可选 `ProfileName`、`Description`、`Category`、`Managed` 属性。
- 修复脱敏诊断包对 `网络 N` / `Network N` 编号 Profile 的分类与计数正则。
- 扫描兼容缺失 `LastWriteTime` 的 Registry Provider 对象。
- NLM COM 不可用时降级为 PowerShell / 注册表诊断，不阻断 Scan。
- 兼容缺失 `IPv4Address` 属性的网络接口对象。
- 隔离可选诊断阶段，避免单项网络组件异常中止整次扫描。
- Safe Repair 显示备份、删除、服务处理、验证与自动回滚进度，并输出最终结果。

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
