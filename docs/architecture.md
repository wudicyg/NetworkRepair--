# Architecture

```text
BAT launcher
    ↓
NetworkRepair.ps1
    ↓
Diagnostics → Risk rules → Backup → Repair → Validation
                                  ↘ Rollback on failure
```

## Safety boundary

注册表在诊断阶段只读；修改限制在明确判定为 Low risk、非当前活动连接、非 Managed 的候选对象。v0.1.x 不进行 Network List Manager Signatures 的无差别清理。


## v0.2.0 diagnostic layers

- Connection Profile
- Network List Manager COM
- IP / DHCP / Gateway / DNS
- NCSI DNS / HTTP probe
- Explainable risk scoring

The write boundary remains unchanged: only explicitly eligible non-active, non-managed candidates can enter Safe Repair.
