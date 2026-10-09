# Diagnostic Codes

诊断代码来自 `src/Diagnostics.ps1`，分两类，**含义与出现位置不同**，排障时不要混用。

## Profile 候选对象上的代码（`Candidates[].DiagnosticCodes`）

编号 Profile 被判定为可疑项时带上，用于解释"为什么它被盯上"。

| Code | 含义 | 触发条件 |
|---|---|---|
| NR1001 | 名称符合编号网络模式（`网络 N` / `Network N`） | `src/Diagnostics.ps1:124` |
| NR1002 | 该编号 Profile 当前仍在使用：Network List Manager 报告已连接，或它仍是活动连接 → **禁止自动删除** | `src/Diagnostics.ps1:129-130` |
| NR1003 | 是 Managed Profile → **禁止自动修改** | `src/Diagnostics.ps1:127` |

## 问题清单代码（`IssueDetails[]`）

按"有问题才追加"的方式生成；**没有任何问题时 `IssueDetails` 是空数组，不产生代码**（不存在"未发现问题"这类占位代码）。

| Code | 严重度 | 含义 |
|---|---|---|
| NR1001 | Low | 发现可安全处理的历史/重复网络 Profile（数量见消息） |
| NR1002 | Warning | 发现高风险或需人工确认的 Profile（数量见消息） |
| NR2001 | Warning | NCSI DNS 探测失败（`dns.msftncsi.com` 解析不通过） |
| NR2002 | Warning | NCSI HTTP Web 探测失败（`www.msftconnecttest.com/connecttest.txt` 状态码或响应内容校验不通过） |
| NR2003 | Warning | NCSI 主动探测已被禁用（`NlaSvc` 的 `EnableActiveProbing = 0`） |
| NR2101 | Warning | 一个或多个已配置的 DNS 服务器无法解析 NCSI DNS 主机 |
| NR2201 | Warning | 一个或多个默认网关不可达 |

> `-SkipConnectivityTest` 会跳过 NCSI 相关探测，因此 NR2001/NR2002/NR2003 不会出现。
> 诊断结果里还有个兼容字段 `Connectivity.TCP443`，它的值来自 NCSI HTTP 探测（HTTP/80），
> 字段名是历史遗留，不代表真的测了 443 端口。

## 不属于诊断代码的失败

备份失败、修复失败、验证失败与自动回滚失败**不使用诊断代码**：它们通过异常、返回对象的
`Success` / `Error` 字段与控制台/日志呈现。修复与恢复的完整结果结构见
[架构设计](architecture.md) 与 `src/Repair.ps1`、`src/Backup.ps1`。
