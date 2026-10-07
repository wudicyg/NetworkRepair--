# Contributing

感谢参与 NetworkRepair。

## 开发原则

任何可能修改网络状态的功能都应遵循：

1. 先诊断；
2. 明确风险；
3. 修改前备份；
4. 记录日志；
5. 修改后验证；
6. 尽可能提供回滚。

## 测试

推荐 Windows PowerShell 5.1 + Pester 5：

```powershell
Invoke-Pester .\tests\NetworkRepair.Tests.ps1
```

请不要在没有虚拟机/还原点的真实工作电脑上测试破坏性功能。
