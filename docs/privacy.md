# NetMedic 隐私说明

本文适用于当前 `main` 开发线（`1.5.0-dev`）及当前最新正式发行版 `1.4.0`。报告默认脱敏的实现由 `src/Diagnostics.ps1` 中的共享摘要函数统一负责。

## 数据收集与联网行为

- NetMedic 不包含遥测上传流程，不会自动把诊断报告、注册表备份、日志或本机网络标识发送给维护者。
- 更新检查只读取 GitHub 上的公开 Release 信息；不会上传本机版本以外的诊断数据，也不会自动下载或替换程序。
- 主动诊断可能执行 DNS 解析、NCSI 连通性探测、向已配置 DNS 服务器查询以及默认网关可达性测试。这些是普通网络请求；NetMedic 不会把本机生成的诊断报告附加到这些请求中。
- 备份、日志及报告保存在本机指定目录。它们是否被同步或备份到其他位置，取决于用户自己的系统与同步工具。

## 默认诊断报告

GUI 的「导出诊断报告」、命令行 `-Mode Report`、`-Mode Scan -Json`、只读验收工具以及一键脱敏诊断 ZIP 默认输出脱敏摘要。摘要会保留排障所需的非标识信息，例如 Windows/PowerShell 版本、网络健康状态、Profile 类型与数量、风险等级、诊断码、DHCP 状态、地址/网关/DNS 数量以及探测结果。

默认摘要不会包含计算机名、适配器名称与描述、Profile 原名、MAC 地址、IP 地址、默认网关/DNS 地址、NetworkId、注册表路径、Network URL 或凭据。候选项按 `ChineseNumbered` / `EnglishNumbered` / `Other` 分类，不输出具体网络名称。

推荐生成可以用于问题反馈的诊断包：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Export-NRSanitizedDiagnosticBundle.ps1
```

或生成只读验收摘要：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -OutputPath .\validation\machine.json
```

脱敏是按字段白名单生成，不等于所有上下文都绝对匿名。分享前仍应检查文件内容，尤其是时间、Windows Build 或非常罕见的环境组合是否会暴露不希望公开的信息。

## 完整诊断详情（仅本机使用）

确有需要时，可以显式选择输出完整报告：

```powershell
NetworkRepair.bat -Mode Report -IncludeSensitiveDetails
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -IncludeSensitiveDetails -OutputPath .\validation\machine-private.json
```

完整报告可能包含计算机名、适配器名称/描述、Profile 名称、MAC 地址、IP/网关/DNS 地址、NetworkId、注册表路径、NCSI 配置信息及诊断原因。此模式会在验收工具中显示警告。**完整报告只应保存在受保护的本机位置，不要附加到公开 Issue、PR 或 Discussions。**

## 备份与日志

- 网络配置备份包含注册表快照与恢复元数据；清理前应确认不再需要回滚。
- 执行日志可能包含 Profile 名称、注册表键标识或操作路径。
- 不要公开上传整个 `backups\`、`logs\` 或原始完整验收报告。对外求助时优先使用默认脱敏的诊断报告/诊断 ZIP。

## 当前平台验证范围

当前已验证并声明支持的主要环境是 Windows 10 + Windows PowerShell 5.1。维护者确认所有已发布脚本版本和单文件 EXE 均已在真实 Windows 10 环境测试通过，Windows 10 验证矩阵已通过。Windows 11 尚未实机验证，本阶段不纳入当前适配目标或兼容性承诺。
