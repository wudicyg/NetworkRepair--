# Architecture

```text
BAT launcher
    ↓
NetworkRepair.ps1
    ↓
Diagnostics
    ↓
Risk rules
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

v0.4.x 将“要做什么”和“怎么执行”分开。Repair Planner 负责把诊断候选转换成显式操作计划，Dry Run 与真实修复共用同一计划，因此预览结果和实际执行路径保持一致。

Safe Repair 的删除动作只能来自 `RemediationAllowed` 候选；Deep Repair 额外提供明确的 `NetworkList\\NewNetworks` 刷新动作，不会因此扩大到 `Signatures\\Managed` / `Signatures\\Unmanaged` 的无差别清理。

## Restore verification

Restore 在导入目标 `.reg` 前创建当前状态的安全备份。导入后会重新导出当前 `NetworkList`，将其与所选备份进行规范化比较；只有快照匹配后才认为恢复成功。

如果恢复后的快照校验失败，会导入恢复前的安全备份，并再次验证安全备份是否已经恢复。若回滚自身也失败，会明确返回回滚失败状态和安全备份路径。

## Diagnostic layers

- Connection Profile
- Network List Manager COM
- IP / DHCP / Gateway / DNS
- NCSI DNS / HTTP probe
- Explainable risk scoring
- Registry Profile GUID ↔ NetworkId correlation

The write boundary remains unchanged: only explicitly eligible non-active, non-managed candidates can enter Safe Repair.
