# Roadmap

> 历史阶段保留已完成条目，**当前待办集中在最后两节**。
> 每个版本实际发布了什么、有哪些行为变化，见 [CHANGELOG.md](../CHANGELOG.md)。

## v0.1.x — 稳定基础层
- [x] 模块化 PowerShell 架构
- [x] Safe Repair
- [x] 自动备份
- [x] 验证与自动回滚
- [x] JSON 报告
- [x] Pester + GitHub Actions
- [x] 发布验证只读证据采集器
- [x] Windows 10 核心实机验证（历史编号 Profile 清理路径）

## v0.2.x — 更智能的诊断
- [x] Network List Manager COM 枚举
- [x] Profile 与活动 Network List 对象交叉验证（基础版）
- [x] 风险评分与可解释原因
- [x] DNS / DHCP / 默认网关诊断
- [x] NCSI DNS / HTTP 诊断
- [x] 统一诊断代码

## v0.3.x — 更完整的修复能力
- [x] 安全网络名称重命名
- [x] 更精细的服务刷新策略（按需、按依赖顺序、有界等待）
- [x] 多级恢复点（分级 + 固定 + 显式清理）

## v0.4.x — 用户体验
- [x] 修复决策/操作计划层
- [x] 网络健康与 Profile 历史遗留双轨判定
- [x] Safe Repair 执行进度与最终结果反馈
- [x] TUI 菜单增强（只读快速状态概览）
- [x] 一键导出脱敏诊断包

## v1.0.x – v1.3.x — 稳定发布与易用性
- [x] 1.0.0 核心实机验收（Windows 10）
- [x] Release 打包自动化（Tag 触发流水线，产物含 SHA-256）
- [x] GitHub Issues / Discussions 工作流
- [x] 单文件 exe 封装（压平 + ps2exe + 提权清单）
- [x] 发布包「单一显眼入口」布局与中文命名
- [x] 发布页附件命名（ASCII 附件名 + 中文标签）
- [x] 图形化界面：诊断总览、一键修复、恢复点管理（WinForms）
- [x] 窗口化 exe（无控制台，双击直接进界面）
- [x] 应用图标（多尺寸 ICO，嵌入 exe 与窗口）
- [x] 自动更新检查（只检查与告知，不自动替换自身）
- [x] 无界面自检 `-Mode GuiSmoke`（CI 可验证界面真的能构建）
- [x] 项目更名为 NetMedic（仓库 `wudicyg/netmedic`，旧地址自动跳转）

## v1.4.x — 当前待办
- [ ] 回归测试矩阵（把已知故障场景固化成用例）
- [ ] Windows 11 / 更多环境扩展验证
- [ ] 更多语言环境测试
- [ ] 目标化 Signature 清理（当前只清理 Profile 与 NewNetworks 记录）

## 更长期（未排期）
- [ ] 自动更新从「提示」扩展到「引导式下载与替换」：需要先解决提权、代码签名与失败回滚，当前刻意只做检查与告知
- [ ] 图形界面多页化（诊断详情 / 恢复点 / 日志分页），当前是单页 + 弹窗
