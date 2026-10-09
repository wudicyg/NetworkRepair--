---
name: Bug report
about: 报告可复现的问题
title: "[Bug] "
labels: bug
assignees: ""
---

## 环境

- Windows 版本：
- PowerShell 版本：
- NetMedic 版本（界面「关于」或 `-Mode Version`）：
- 使用的产物（便携 exe / 完整 zip / 源码运行）：

## 问题描述

请描述实际发生了什么。

## 复现步骤

1.
2.
3.

## 诊断报告

软件界面上的「导出诊断报告」按钮产出的是**脱敏诊断包**，可以直接附上；命令行 `-Mode Report` 产出的是
**完整**报告（含 MAC 地址、IP 地址与 NetworkId），公开提交前请先自行脱敏，或改用：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Export-NRSanitizedDiagnosticBundle.ps1
```

> 请不要提交 Wi-Fi 密码、VPN 凭据、令牌、私钥或其他敏感信息。
