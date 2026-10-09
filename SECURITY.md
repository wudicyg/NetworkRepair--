# Security Policy

NetMedic 具有修改 Windows 网络配置和注册表的能力。

## 隐私与诊断文件

- NetMedic 不自动上传诊断报告、注册表备份、日志或本机网络标识；更新检查只读取 GitHub 公开 Release 信息。
- GUI 和命令行诊断报告默认导出脱敏摘要；`-Mode Scan -Json` 同样默认只输出白名单摘要。完整诊断详情必须显式添加 `-IncludeSensitiveDetails`，并应只保存在受保护的本机位置。
- `Invoke-NRReadOnlyValidation.ps1` 默认输出脱敏验收摘要；使用 `-IncludeSensitiveDetails` 时可能包含计算机名、Profile/接口名、NetworkId、注册表路径及 IP 配置。
- 公开提交问题时，请使用一键脱敏诊断 ZIP，并在上传前检查内容。具体字段说明见 [隐私说明](docs/privacy.md)。

请不要在公开 Issue、PR 或 Discussions 中提交：

- Wi-Fi 密码或 VPN 凭据
- 访问令牌、私钥或身份验证信息
- 未脱敏的完整诊断报告、注册表备份或运行日志
- 完整企业网络拓扑、内网地址清单、NetworkId 或注册表路径等敏感信息

## 漏洞报告

发现可能导致任意注册表删除、权限提升、凭据泄露或远程执行的漏洞，请优先通过 [GitHub 私密安全报告](https://github.com/wudicyg/netmedic/security/advisories/new) 报告，不要直接公开利用细节。
