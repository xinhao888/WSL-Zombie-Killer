# StartWSL — WSL 开机自启 + 僵尸进程清理 / Auto-start WSL on boot + zombie cleanup

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
开机 10 秒后
  ├── taskkill /F /IM wslservice.exe  （清除残留僵尸）
  ├── Start-Sleep 5
  ├── wsl                               （启动默认发行版）
  ├── Start-Sleep 20                    （等待完全启动）
  └── 持续监测循环（每 3 秒）：
        wslhost.exe 存在？
          ├── 是 → 不杀 wslservice，继续监测
          └── 否 → 等 4 秒 → taskkill wslservice（不自动拉起）
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
# 检查任务
schtasks /Query /TN "StartWSL" /FO LIST

# 检查 WSL 进程（wslhost 存在 = WSL 存活）
Get-Process wslhost, wslservice -ErrorAction SilentlyContinue | Format-Table Id, Name

# 检查默认发行版是否可访问
wsl -- echo ok
```

### 系统要求

- Windows 10 / 11
- WSL 2 已安装
- 当前用户下已有 WSL 发行版

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
10 seconds after boot
  ├── taskkill /F /IM wslservice.exe  (clear residual zombies)
  ├── Start-Sleep 5
  ├── wsl                               (start default distro)
  ├── Start-Sleep 20                    (wait for full startup)
  └── Monitoring loop (every 3s):
         wslhost.exe present?
           ├── Yes → skip, continue monitoring
           └── No  → wait 4s → taskkill wslservice (no auto-restart)
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
# Check task
schtasks /Query /TN "StartWSL" /FO LIST

# Check WSL processes (wslhost present = WSL alive)
Get-Process wslhost, wslservice -ErrorAction SilentlyContinue | Format-Table Id, Name

# Check default distro is reachable
wsl -- echo ok
```

### Requirements

- Windows 10 / 11
- WSL 2 installed
- A WSL distro registered under the current user
