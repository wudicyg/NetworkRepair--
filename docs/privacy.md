# NetMedic 隐私说明

本文适用于当前 \`main\` 开发线（\`1.5.0-dev\`）及最新正式发行版 \`1.4.0\`。本文说明程序实际会进行哪些网络访问、诊断文件的默认脱敏边界，以及用户如何安全地分享排障材料。

## 数据收集与联网行为

- NetMedic 不包含遥测上传流程，不会自动向维护者上传诊断报告、注册表备份、运行日志或本机网络标识。
- 更新检查只读取 GitHub 公开的 Release 元数据，用来比较版本并显示下载页面；不会自动下载或替换程序，也不会把诊断结果附加到更新请求。
- 主动诊断可能执行 DNS 解析、NCSI 连通性探测、向本机已配置的 DNS 服务器查询，以及默认网关可达性测试。这些会产生普通的 DNS 或网络请求；与访问任何在线服务一样，目标服务或网络服务提供商可能看到正常连接所需的请求元数据。NetMedic 不会把诊断报告作为这些请求的载荷上传。
- 配置备份、运行日志和导出文件保存在本机目录。它们是否被云盘或其他同步软件复制，由用户的系统和工具设置决定。

## 默认诊断报告与脱敏边界

GUI 的「导出诊断报告」、命令行 \`-Mode Report\`、\`-Mode Scan -Json\`、只读验收工具，以及一键脱敏诊断 ZIP，默认使用共享的字段白名单摘要。原始诊断对象不会直接作为默认分享报告输出。

默认摘要可以保留排障所需的概要信息，例如 Windows / PowerShell 版本、健康状态、历史 Profile 分类和数量、风险等级与诊断代码、DHCP 状态、地址 / 网关 / DNS 的数量、探测结果及诊断阶段错误数量。

默认摘要不会包含计算机名、适配器名称与描述、具体 Profile 名称、MAC 地址、IP 地址、网关或 DNS 服务器地址、NetworkId、注册表路径、NCSI URL、原始异常文本或凭据。编号网络候选仅以 \`ChineseNumbered\`、\`EnglishNumbered\` 或 \`Other\` 分类输出。

生成推荐的问题反馈诊断包：

\`\`\`powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Export-NRSanitizedDiagnosticBundle.ps1
\`\`\`

生成只读验收摘要：

\`\`\`powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -OutputPath .\validation\machine.json
\`\`\`

脱敏不是对所有上下文绝对匿名。时间戳、Windows Build、PowerShell 版本或非常罕见的环境组合仍可能帮助识别环境。分享前请检查摘要文件内容，不要仅凭文件名判断安全性。

## 完整诊断详情（仅本机私下排障）

只有在确实需要完整网络标识或底层诊断信息时，才显式启用敏感详情模式。例如：

\`\`\`powershell
NetworkRepair.bat -Mode Report -IncludeSensitiveDetails
NetworkRepair.bat -Mode Scan -Json -IncludeSensitiveDetails
powershell.exe -ExecutionPolicy Bypass -File .\tools\Invoke-NRReadOnlyValidation.ps1 -IncludeSensitiveDetails -OutputPath .\validation\machine-private.json
\`\`\`

完整诊断可能包含计算机名、适配器名称与描述、Profile 名称、MAC 地址、IP / 网关 / DNS 地址、NetworkId、注册表路径、NCSI 配置信息和详细错误原因。启用后，程序会显示警告。完整文件只应保存在受保护的本机位置，不要附加到公开 Issue、PR 或 Discussions。

修复、恢复、重命名等操作结果和运行日志用于本机执行及审计，可能包含本地路径、网络名称或操作标识；不要把原始日志或完整操作输出直接公开。公开求助时优先使用默认脱敏诊断 ZIP，并在上传前人工检查。

## 备份与日志

- 网络配置备份包含注册表快照与恢复元数据；其用途是本机回滚，不是公开分享。
- 执行日志可能包含 Profile 名称、注册表键标识、文件路径或操作原因。
- 不要公开上传整个 \`backups\\\`、\`logs\\\` 或敏感模式生成的验收报告。若需要提交完整证据，请先通过私密渠道与维护者沟通。

## 当前平台验证范围

当前声明支持并已实机验证的主要环境是 Windows 10 + Windows PowerShell 5.1。维护者确认所有已发布脚本版本和单文件 EXE 均已在真实 Windows 10 环境测试通过，Windows 10 验证矩阵已通过。Windows 11 当前没有可供维护者实测的设备，因此不纳入本阶段适配目标，也不作已验证兼容性承诺。
