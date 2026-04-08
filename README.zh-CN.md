<div align="center">

# ⚡ Codex Rate Watcher

### 再也不会在编程途中被限速打断

一款极速 macOS 菜单栏应用，实时监控 [OpenAI Codex](https://openai.com/index/codex/)（ChatGPT Pro / Team）的速率限制用量 —— 支持多账号管理、消耗速率预测和智能切换。

[![en](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![zh-CN](https://img.shields.io/badge/lang-简体中文-red.svg)](README.zh-CN.md)
[![ja](https://img.shields.io/badge/lang-日本語-green.svg)](README.ja.md)
[![ko](https://img.shields.io/badge/lang-한국어-yellow.svg)](README.ko.md)
[![es](https://img.shields.io/badge/lang-Español-orange.svg)](README.es.md)
[![fr](https://img.shields.io/badge/lang-Français-purple.svg)](README.fr.md)
[![de](https://img.shields.io/badge/lang-Deutsch-black.svg)](README.de.md)

![macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-brightgreen)
![Zero Dependencies](https://img.shields.io/badge/dependencies-zero-success)

<p>
  <img src="docs/screenshot.jpg" width="440" alt="Codex Rate Watcher — 实时监控 OpenAI Codex ChatGPT 速率限制的 macOS 菜单栏应用" />
</p>

*实时配额监控 · 消耗速率预测 · 多账号切换 · 重置倒计时*

</div>

---

## 🤯 痛点

你正处于心流状态，和 Codex 结对编程，重构一个关键模块——然后突然，**速率限制的墙迎面撞来**。没有警告，没有倒计时，只有一个冰冷的 `429 Too Many Requests`。

你等待，你刷新，你完全不知道配额什么时候重置，也不知道自己消耗了多快。

**Codex Rate Watcher** 彻底解决这个问题。

## 🎯 核心功能

Codex Rate Watcher 驻留在 macOS 菜单栏，让你对 OpenAI Codex / ChatGPT 的速率限制用量**一目了然**：

| 能力 | 描述 |
|---|---|
| **📊 实时配额追踪** | 同时监控 5 小时主配额、周配额和代码审查配额 |
| **🔥 消耗速率预测** | 精确预测配额耗尽时间（如"预计 1h32min 后耗尽，14:30 重置"） |
| **⏰ 重置倒计时** | 每张配额卡片都显示重置时间——不仅仅是被封锁时 |
| **👥 多账号管理** | 自动捕获账号快照；Plus 和 Team 账号并行管理 |
| **🧠 智能切换** | 加权评分算法推荐最佳切换目标 |
| **🔄 孤儿快照自动整合** | 启动时自动发现并注册未索引的认证快照 |
| **🏷️ 套餐标识** | UI 中清晰标注 Plus / Team |
| **🎨 深色主题 UI** | Linear 风格设计，配额卡片颜色编码 |

## ✨ 功能亮点

### 📊 三维度配额追踪

大多数开发者只有在 Codex 停止响应*之后*才发现自己撞了限速墙。Codex Rate Watcher 能**同时追踪三个配额维度** —— 5 小时主窗口、周聚合窗口和代码审查限制 —— 在菜单栏一眼全览。

### 🔥 智能消耗速率预测引擎

内置预测器使用**线性回归**分析真实用量样本，精确告诉你每个配额*什么时候*会耗尽。不用猜，不用心算 —— 直接显示 *"预计 1h32min 后耗尽，14:30 重置"*。

### ⏰ 全时段重置倒计时

重置时间不只在你被封锁时才显示。**每张配额卡片始终显示重置时间**，即使你正在活跃编程中。你随时知道还有多少余量，以及下一个窗口何时开启。

### 👥 多账号管理 + 智能切换

管理多个 ChatGPT Pro 或 Team 账号？应用自动捕获认证快照，并通过**加权可用性算法**为每个配置文件评分（主配额 × 3.2 + 周配额 × 0.45 + 审查 × 0.08，低余额惩罚）。一键切换，当前认证自动备份。

### 🍎 Apple 渠道订阅也能用

如果你的 ChatGPT Plus 是通过 App Store 订阅的，也没问题。Codex Rate Watcher 读取的是你本机的 Codex 登录态，而不是支付渠道。

<p>
  <img src="docs/apple-receipt.jpg" width="520" alt="Apple 收据：通过 App Store 订阅 ChatGPT Plus（月度）" />
</p>

### 💸 Token Cost 悬停详情

现在 `Token Cost` 卡片已经支持按天悬停查看详情。鼠标沿着柱状图横向移动时，可以直接看到对应日期、当天成本、token 总量、cache 占比和主模型，不用再额外打开完整 dashboard。

<p>
  <img src="docs/screenshot-token-cost-hover.jpg" width="520" alt="Token Cost 卡片悬停详情：展示单日日期、成本、tokens、cache 占比与主模型" />
</p>

### 🔄 自愈式配置文件存储

**孤儿快照自动整合引擎**在启动时扫描配置文件目录，自动发现未索引的认证快照并注册（SHA256 指纹去重）。即使索引文件损坏，你的账号也不会丢失。

### 🔔 智能预警系统

通过**可配置阈值通知**（50%、30%、15%、5%）提前预警配额耗尽。告警通过 **macOS 原生通知**推送，按重置周期自动去重，同一告警不会重复打扰。随着配额下降，紧急程度自动升级 —— 低阈值告警会附带**提示音**，即使你正在专注编码也能及时注意到。

### 🎨 动态状态栏图标

菜单栏图标不再是静态的。它会根据配额健康度**实时变色** —— 余量充足时为**绿色**，用量攀升时为**黄色**，需要减速时为**橙色**，配额告急时为**红色**。无需打开面板即可**一目了然**，让你随时掌握配额状态。

### 🛡️ 隐私优先架构

所有数据保存在本地。应用仅与官方 ChatGPT Usage API 通信（`chatgpt.com/backend-api/wham/usage`）。无分析、无遥测、无第三方服务。你的认证令牌绝不离开本机。

### 更多亮点

- **菜单栏状态** —— 剩余百分比始终可见
- **五级可用性排序** —— 可用 → 即将耗尽 → 已封锁 → 错误 → 未验证
- **认证文件监听** —— 通过 kqueue 实时检测 `codex login`
- **套餐标识** —— 主卡片标题清晰显示 Plus / Team
- **调试窗口模式** —— `--window` 标志启动独立窗口
- **零依赖** —— 纯 Apple 系统框架，无第三方包
- **自动化 CI 发布** —— GitHub Actions 在每个版本标签自动构建 Apple Silicon 和 Intel 双架构 `.app` 包

## 📥 下载安装

在 [Releases](https://github.com/sinoon/codex-rate-watcher/releases) 页面下载预编译的 `.app` 包——**无需安装 Xcode 或 Swift 工具链**。

| 芯片 | 下载 |
|---|---|
| **Apple Silicon**（M1 / M2 / M3 / M4） | [最新版 — Apple Silicon](https://github.com/sinoon/codex-rate-watcher/releases/latest) |
| **Intel**（x86_64） | [最新版 — Intel](https://github.com/sinoon/codex-rate-watcher/releases/latest) |

1. 下载对应芯片的 `.zip` 文件
2. 解压后将 **Codex Rate Watcher.app** 拖入 `/Applications`
3. 启动——它会出现在菜单栏（不在 Dock 中）
4. 确保 Codex CLI 已登录（`~/.codex/auth.json` 必须存在）

> **首次启动：** 应用未经公证。请右键 → **打开**，或前往系统设置 → 隐私与安全性 → **仍要打开**。

---

## 🚀 从源码构建

如果你更喜欢自行编译：

### 前置条件

- **macOS 14**（Sonoma）或更高版本
- **Codex CLI** 已安装并登录（`~/.codex/auth.json`）
- **Swift 6.2+**（Xcode 26 或 [swift.org](https://swift.org) 工具链）

### 构建与运行

```bash
# 克隆仓库
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher

# 直接运行（调试模式）
swift run

# 或构建 release .app 包
swift build -c release
./scripts/build_app.sh 1.0.0
# → dist/Codex Rate Watcher.app
```

### 调试窗口模式

```bash
swift run CodexRateWatcherNative -- --window
```

以独立窗口启动，而非菜单栏弹窗——适合截图和 UI 调试。

## 🔬 工作原理

```
~/.codex/auth.json            ← Codex CLI 登录时写入
        │
        ▼
   AuthStore（读取令牌）
        │
        ▼
   UsageAPIClient ──────────► chatgpt.com/backend-api/wham/usage
        │
        ▼
   UsageMonitor（每 60 秒轮询）
    │         │
    │         ▼
    │    SampleStore（持久化样本）
    │         │
    │         ▼
    │    UsageEstimator（消耗速率预测）
    │
    ▼
   AuthProfileStore（多账号管理）
    │         │
    │         ▼
    │    AuthFileWatcher（检测账号变更）
    │
    ▼
   AppDelegate（状态栏）◄──► PopoverViewController（GUI）
```

### 消耗速率预测引擎

预测器使用**线性回归**分析时间序列用量样本：

1. 筛选当前速率限制窗口内的样本（按 `reset_at` 匹配）
2. 选取近期样本（主配额回溯 3h，周配额回溯 3d）
3. 计算 `Δ 用量 / Δ 时间` → 每小时消耗率
4. 预测 `剩余 / 速率` → 耗尽时间
5. 如果窗口在耗尽前重置 → "按当前速率，重置前不会耗尽"

### 智能账号评分

```
score  = min(主配额%, 周配额%) × 3.2    // 均衡可用性（最高权重）
score += 主配额%               × 1.1    // 5h 余量
score += 周配额%               × 0.45   // 周余量
score += 审查配额%             × 0.08   // 代码审查余量
if 即将耗尽: score -= 28                 // 惩罚
if 当前账号: score += 4                  // 留任奖励
```

得分最高的账号被推荐。切换时自动备份当前 `auth.json`。

## 📂 数据存储

所有数据保存在本地。除了调用官方 ChatGPT Usage API，没有任何数据离开你的电脑。

```
~/Library/Application Support/CodexRateWatcherNative/
├── samples.json         # 用量历史（保留 10 天）
├── profiles.json        # 账号配置文件索引
├── auth-profiles/       # 保存的 auth.json 快照（SHA256 指纹）
└── auth-backups/        # 切换前的 auth.json 备份
```

## ⚙️ 技术栈

| 组件 | 技术 |
|---|---|
| 语言 | Swift 6.2 |
| UI 框架 | AppKit（纯代码，无 SwiftUI/XIB） |
| 构建系统 | Swift Package Manager |
| 并发 | Swift Concurrency（async/await, Actor） |
| 网络 | URLSession |
| 加密 | CryptoKit（SHA256 指纹） |
| 文件监听 | GCD DispatchSource（kqueue） |
| 依赖 | **无** —— 纯系统框架 |

## 🤝 贡献

欢迎贡献！你可以：

- 提交 Issue 报告 Bug 或提出功能需求
- 提交 Pull Request
- 分享你的多账号工作流技巧

## 📄 许可证

[MIT](LICENSE) © 2026
