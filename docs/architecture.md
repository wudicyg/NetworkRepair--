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

## Diagnostic layers

- Connection Profile
- Network List Manager COM
- IP / DHCP / Gateway / DNS
- NCSI DNS / HTTP probe
- Explainable risk scoring
- Registry Profile GUID ↔ NetworkId correlation

The write boundary remains unchanged: only explicitly eligible non-active, non-managed candidates can enter Safe Repair.


## Health vs. Profile hygiene

NetworkRepair treats network connectivity health and Network List Profile hygiene as two independent dimensions.

A machine can be **Healthy** while still containing historical numbered Profiles such as `网络 2`, `网络 3`, or `Network 4`. In that case the report says the network is healthy but recommends historical Profile cleanup, and the Repair Planner may still generate safe deletion actions for inactive, non-Managed candidates.

Conversely, a healthy connection does not make an active or Managed numbered Profile eligible for deletion. Safety gates remain authoritative.

When there is no historical Profile cleanup candidate and the network is healthy, the repair decision is explicitly `NoAction`; the tool does not enter a destructive repair path merely because it was invoked for testing.
