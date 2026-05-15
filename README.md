# StartWSL — WSL 开机自启 + 僵尸进程清理 / Auto-start WSL on boot + zombie cleanup

![Windows](https://img.shields.io/badge/Windows-10%2022H2-blue)
![WSL](https://img.shields.io/badge/WSL-2-green)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-yellow)
![License](https://img.shields.io/badge/License-MIT-orange)

[中文](#中文) | [English](#english)

---

## 中文

### 简介

Windows 10 22H2 上 LxssManager 存在已知 bug：`wslservice.exe` 在 WSL 退出后可能残留为僵尸进程，且 `wsl --shutdown` 100% 产生此类僵尸。每次开机时自动清理残留僵尸并启动 WSL，然后持续监控 WSL 存活状态，发现 wslhost 消失后自动清理僵尸 wslservice。

### 文件结构

| 文件 | 作用 |
|------|------|
| `start-wsl.ps1` | 核心脚本：启动 WSL + 持续监测 wslhost |
| `install-task.ps1` | 安装/卸载器，自动检测自身路径 |
| `一键安装.vbs` | 双击自动提权安装计划任务 |
| `一键卸载.vbs` | 双击自动提权卸载计划任务 |
| `README.md` | 本文件 |

### 安装

双击 `一键安装.vbs`，UAC 弹窗点"是"。

或者管理员 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<路径>\install-task.ps1"
```

### 卸载

双击 `一键卸载.vbs`，UAC 弹窗点"是"。

或者管理员 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<路径>\install-task.ps1" -Uninstall
```

### 工作原理

```
Boot
  │ (delay 10s)
  ├─ [Step 1] taskkill /F /IM wslservice.exe  ← 清除残留僵尸
  ├─ [Step 2] Start-Sleep 5
  ├─ [Step 3] wsl                               ← 启动默认发行版
  ├─ [Step 4] Start-Sleep 20                    ← 等待完全启动
  └─ [Monitor Loop] (every 3s):
        wslservice running + wslhost missing?
          ├─ Yes → wait 4s → double check
          │         ├─ still zombie → taskkill wslservice
          │         └─ wslhost back → skip (safe)
          └─ No → skip
```

- `wslservice.exe` — WSL 的 Windows 侧服务进程
- `wslhost.exe` — WSL 与 Windows 交互的代理进程，存在即 WSL 存活
- 杀僵尸后不自动拉起，避免反复崩溃；用户手动 `wsl` 后自动恢复
- 4 秒双确机制：首次发现 wslhost 缺失不立即杀，等 4 秒再确认一次，避免启动期误杀

### 计划任务配置

| 项目 | 值 |
|------|-----|
| 任务名 | StartWSL |
| 触发 | 开机（BootTrigger），延迟 10 秒 |
| 身份 | 当前用户（S4U，无需登录） |
| 权限 | Highest（管理员） |

### 验证

```powershell
# 检查进程
Get-Process wslhost, wslservice -ErrorAction SilentlyContinue | Format-Table Id, Name, StartTime

# 检查 WSL 连通性
wsl -- echo ok

# 监控循环活跃
Get-Process wslservice -ErrorAction SilentlyContinue | Select-Object Id, StartTime
```

### 系统要求

- Windows 10 / 11
- WSL 2 已安装
- 当前用户下已有 WSL 发行版

### 为什么选择此工具

| 场景 | 社区方案 | WSL-Tools |
|------|---------|-----------|
| 开机清理僵尸 | ❌ 手动 taskkill | ✅ 全自动 |
| 运行中监控 | ❌ 无 | ✅ 3s 轮询 |
| 防误杀 | ❌ 无 | ✅ 4s 双确认 |
| 安装卸载 | ❌ 手打命令 | ✅ 双击 VBS |

---

## English

### Overview

On Windows 10 22H2, LxssManager has a known bug: `wslservice.exe` can become a zombie after WSL exits, and `wsl --shutdown` produces such zombies 100% of the time. This tool kills residual zombies on boot, starts WSL, and continuously monitors WSL health via `wslhost.exe` presence.

### Files

| File | Purpose |
|------|---------|
| `start-wsl.ps1` | Core script: launch WSL + monitor wslhost |
| `install-task.ps1` | Installer/uninstaller with auto path detection |
| `一键安装.vbs` | One-click install with auto-elevation |
| `一键卸载.vbs` | One-click uninstall with auto-elevation |
| `README.md` | This file |

### Install

Double-click `一键安装.vbs`, confirm UAC prompt.

Or from admin PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path>\install-task.ps1"
```

### Uninstall

Double-click `一键卸载.vbs`, confirm UAC prompt.

Or from admin PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path>\install-task.ps1" -Uninstall
```

### How It Works

```
Boot
  │ (delay 10s)
  ├─ [Step 1] taskkill /F /IM wslservice.exe  ← clear residual zombies
  ├─ [Step 2] Start-Sleep 5
  ├─ [Step 3] wsl                               ← start default distro
  ├─ [Step 4] Start-Sleep 20                    ← wait for full startup
  └─ [Monitor Loop] (every 3s):
        wslservice running + wslhost missing?
          ├─ Yes → wait 4s → double check
          │         ├─ still zombie → taskkill wslservice
          │         └─ wslhost back → skip (safe)
          └─ No → skip
```

- `wslservice.exe` — Windows-side WSL service process
- `wslhost.exe` — WSL-Windows proxy; present = WSL is alive
- Zombies are killed but WSL is NOT auto-restarted to avoid crash loops; manual `wsl` restarts the cycle
- 4s double-check: first detection of missing wslhost waits 4 seconds before confirming, avoiding startup false kills

### Task Configuration

| Item | Value |
|------|-------|
| Task Name | StartWSL |
| Trigger | Boot, delayed 10 seconds |
| Principal | Current user (S4U, no login required) |
| Run Level | Highest (admin) |

### Verification

```powershell
# Check processes
Get-Process wslhost, wslservice -ErrorAction SilentlyContinue | Format-Table Id, Name, StartTime

# Check WSL is reachable
wsl -- echo ok

# Check monitor loop is active
Get-Process wslservice -ErrorAction SilentlyContinue | Select-Object Id, StartTime
```

### Requirements

- Windows 10 / 11
- WSL 2 installed
- A WSL distro registered under the current user

### Why This Tool

| Scenario | DIY Approach | WSL-Tools |
|----------|-------------|-----------|
| Bootup zombie cleanup | ❌ Manual taskkill | ✅ Fully automatic |
| Runtime monitoring | ❌ None | ✅ 3s polling |
| False-positive prevention | ❌ None | ✅ 4s double-check |
| Install/uninstall | ❌ Manual commands | ✅ Double-click VBS |
