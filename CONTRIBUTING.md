# Contributing

感谢参与 NetworkRepair。完整的反馈渠道、分支命名、PR 门禁与发布流程见 [协作流程](docs/collaboration.md)。

## 开发原则

任何可能修改网络状态的功能都应遵循：

1. 先诊断；
2. 明确风险；
3. 修改前备份；
4. 记录日志；
5. 修改后验证；
6. 尽可能提供回滚。

## 提交方式

- 所有改动走分支 + PR，禁止直接推送 `main`。
- 分支命名：`fix/<主题>`、`feat/<主题>`、`docs/<主题>`、`test/<主题>`、`release/<版本>`。
- 提交信息使用 Conventional Commits：`fix: …`、`feat: …`、`docs: …`、`test: …`、`release: …`。
- PR 必须通过 CI 门禁：Windows PowerShell 5.1 与 PowerShell 7 的语法解析 + Pester，以及发布包冒烟测试。

## 测试

推荐 Windows PowerShell 5.1 + Pester 5：

```powershell
Invoke-Pester .\tests\NetworkRepair.Tests.ps1
```

请不要在没有虚拟机/还原点的真实工作电脑上测试破坏性功能。

## 敏感信息

不要提交 Wi-Fi 密码、VPN 凭据、访问令牌、私钥或完整企业网络拓扑。需要附诊断信息时，请使用一键脱敏诊断包导出器：

```powershell
.\tools\Export-NRSanitizedDiagnosticBundle.ps1
```
