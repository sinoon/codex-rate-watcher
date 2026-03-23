# Codex Rate Watcher — Killer Feature Roadmap

> 目标：从 "OpenAI 额度监控小工具" 升级为 **AI 开发者必备基础设施**

---

## P0 — Cost Dashboard（实时花费看板）

**痛点**：开发者不知道自己每小时/每天实际消耗了多少价值，月底被账单吓到。

### 核心指标

| 指标 | 含义 | 数据来源 |
|------|------|----------|
| Subscription Cost | Plus $20/mo, Team $25/user/mo | `planType` 字段 |
| Utilization Rate | 每个重置周期内实际消耗占比 | `usedPercent` 历史采样 |
| Effective $/day | 基于利用率换算的等效日花费 | subscription ÷ 30 ÷ utilization |
| Burn Rate ($/hr) | 当前消耗速率的美元等价 | `percentPerHour` × subscription映射 |
| Active Hours/day | 每天实际编码小时数 | 采样间隔内 usage 变化 > 0 的时段 |

### 数据层设计

```
CodexRateKit/CostTracker.swift
├── CostRecord          // 单次采样：timestamp, quotaType, usedPercent, burnRate
├── CycleSummary        // 单个重置周期：peakUsage, utilization, activeMinutes  
├── DailyDigest         // 日汇总：cycles[], avgUtilization, effectiveCost
└── CostTracker (enum)  // 静态方法：record(), todaySummary(), weeklyStats()
    └── 存储：AppPaths.costHistoryFile (JSON, 自动滚动保留30天)
```

### UI 设计

**Popover Card — "Cost" 卡片**（位于 Quota Card 与 Relay Card 之间）：
```
┌─────────────────────────────────────┐
│ COST INSIGHT                        │
│                                     │
│  $0.67/hr    $5.2 today   63% util  │
│  ▁▂▃▅▇█▇▅▃▂▁▁▁▁▂▃▅▇    ← 24h 火花线 │
│                                     │
│  Plus · $20/mo · 本月已用 $12.4      │
└─────────────────────────────────────┘
```

**Menu Bar**（可选显示模式）：
- 默认：`44% · $0.67/hr`
- 紧凑：`44%`

### 预算告警

- 日预算阈值：超过 $X/天 时推送通知
- 月预算预测：按当前趋势将超过 $Y/月 时提前告警
- 利用率告警：利用率低于 X% 时提示（你在浪费钱）

---

## P0 — CLI Proxy（透明代理层）

**杀手锏**：零侵入接管所有 API 请求，自动路由到最优账号。

### 架构

```
用户代码 → OPENAI_API_BASE=localhost:19876 → codex-rate-watcher proxy
  ├── 选择当前最优账号 key（基于 RelayPlanner）
  ├── 转发请求到 api.openai.com
  ├── 精确记录每次请求的 token 消耗
  ├── 429 自动 failover 到下一个账号
  └── 所有流量自动计入 Cost Dashboard
```

### 实现方案

- Swift NIO 轻量 HTTP server（~200行核心代码）
- `codex-rate proxy --port 19876` CLI 命令
- Header 注入：替换 Authorization Bearer token
- 流式响应透传（SSE streaming）
- 精确 token 计数 → 喂入 CostTracker

### 用户体验

```bash
# 一行配置，零代码改动
export OPENAI_API_BASE=http://localhost:19876/v1

# 后台启动
codex-rate proxy --port 19876 --auto-relay

# 所有工具自动走代理：Cursor / Copilot / Continue / Aider ...
```

---

## P1 — Multi-Provider 支持

**扩大用户群10倍**：从 OpenAI 专属工具升级为全 Provider 监控平台。

### 目标 Provider

| Provider | Rate Limit API | 难度 |
|----------|---------------|------|
| OpenAI (Codex) | ✅ 已实现 | - |
| Claude API | `x-ratelimit-*` headers | 低 |
| Gemini | Usage API | 中 |
| DeepSeek | headers | 低 |
| Groq | `x-ratelimit-*` headers | 低 |

### 架构改造

- `Provider` protocol：统一的额度查询接口
- `ProviderRegistry`：注册 + 发现
- 每个 Provider 独立 polling interval
- 跨 Provider 接力：OpenAI 耗尽 → 自动切到 Claude

---

## P1 — Usage Analytics（使用分析）

### 可视化

- **24h 消耗曲线**：迷你 sparkline 在 Cost Card 中
- **7d 日利用率柱状图**：独立窗口或展开面板
- **模式识别**：「你的使用高峰在 14:00-17:00，建议预留更多额度」
- **账号健康度**：每个账号的历史利用率热力图

### 数据存储

- 本地 SQLite（隐私第一，零云依赖）
- 自动 vacuum 保留 90 天
- 导出 CSV/JSON

---

## P2 — Team Mode（团队共享）

### 方案

- 轻量同步：共享 JSON via iCloud / Dropbox / Cloudflare Workers
- 团队看板：谁在什么时间消耗了多少
- 共享账号池的智能调度
- 角色权限：admin 管理账号，member 只读

---

## 实施顺序

```
v1.8.0  ✅ Relay Planning（已发布）
v1.9.0  → Cost Dashboard（本次实现）
v2.0.0  → CLI Proxy
v2.1.0  → Multi-Provider
v2.2.0  → Usage Analytics (SQLite)
v3.0.0  → Team Mode
```

---

## v1.9.0 实施清单

- [ ] `CodexRateKit/CostTracker.swift` — 数据层
- [ ] `AppPaths.swift` — 添加 costHistoryFile 路径
- [ ] `Copy.swift` — Cost 相关文案
- [ ] `PopoverViewController.swift` — Cost 卡片 UI
- [ ] `UsageMonitor.swift` — 集成 CostTracker，State 扩展
- [ ] `AppDelegate.swift` — 菜单栏 cost 显示
- [ ] `main.swift` — CLI `cost` 命令
- [ ] `README.md` — 更新文档 + 截图
- [ ] Git tag v1.9.0
