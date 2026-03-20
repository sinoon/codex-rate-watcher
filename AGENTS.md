# AGENTS.md

## 协作偏好

- 默认使用中文回复。
- 代码注释使用英文。
- commit message 使用 conventional commits 格式，例如 `feat:`、`fix:`、`chore:`。
- git 分支名默认使用 `feat/` 前缀。
- 代码风格以 2 空格缩进为准。
- 遇到不确定的问题先确认，不要直接拍板。

## 项目定位

- 这是一个原生 macOS 14+ 菜单栏应用，用来监控 OpenAI Codex / ChatGPT 的额度使用情况。
- 仓库不是 TypeScript 主仓，核心实现是 Swift + SwiftPM；TypeScript 只出现在 `raycast-extension/`。
- 当前仓库一共提供三层交付面：
  - GUI 菜单栏应用 `CodexRateWatcherNative`
  - CLI 工具 `codex-rate`
  - Raycast 扩展 `raycast-extension/`
- 项目依赖本机 Codex 登录态，默认从 `~/.codex/auth.json` 读取认证信息。

## 当前确认的代码结构

- `Package.swift`
  - SwiftPM 单仓，当前没有 Xcode `.xcodeproj`。
  - 产物分为 `CodexRateKit`、`CodexRateWatcherNative`、`codex-rate`。
- `Sources/CodexRateKit/`
  - 放共享领域逻辑。
  - `AuthStore.swift` 负责读取 `~/.codex/auth.json`，解析 access token、account id、auth mode，并从 JWT 中提取 email。
  - `UsageAPIClient.swift` 直接请求 `https://chatgpt.com/backend-api/wham/usage`。
  - `AppPaths.swift` 定义本地持久化目录。
- `Sources/CodexRateWatcherNative/`
  - 原生 GUI 菜单栏应用。
  - `main.swift` 只有两个模式：默认菜单栏模式，或 `--window` 调试窗口模式。
  - `AppDelegate.swift` 是 GUI 入口，负责状态栏图标、popover、右键菜单、手动刷新、通知开关、快捷键开关。
  - `UsageMonitor.swift` 是运行时核心，负责轮询、状态聚合、profile 校验、切换建议、observer 分发。
  - `PopoverViewController.swift` 是当前主 UI，使用 AppKit 手写布局，现状是单列深色面板，不是多列布局。
  - `Persistence.swift` 管理样本、profile 索引、auth 快照和切换前备份。
  - `AuthFileWatcher.swift` 监听 `~/.codex/` 目录变化，自动吸收 `codex login` 后的新 auth。
- `Sources/codex-rate/`
  - CLI 入口，支持 `status`、`profiles`、`watch`、`history`。
  - `--json` 是给脚本和 Raycast 用的稳定输出面。
- `raycast-extension/`
  - 通过调用 CLI 获取数据，不是自己直连 Usage API。

## 当前确认的运行链路

1. `AuthStore` 从 `~/.codex/auth.json` 读取当前登录态。
2. `UsageAPIClient` 用 bearer token 请求 Usage API。
3. `UsageMonitor` 启动后会：
   - 先加载历史样本；
   - 捕获当前 auth 快照；
   - 立即做一轮刷新；
   - 每 60 秒自动刷新一次；
   - 每 5 分钟补做一次 profile 校验；
   - 在监听到 auth 文件变化后，经过 500ms debounce 再同步。
4. `SampleStore` 把使用样本写到本地，保留最近 10 天。
5. `AuthProfileStore` 会：
   - 自动记录当前 auth 快照；
   - 启动时回收未入索引的孤儿快照；
   - 切换 profile 前先备份当前 `auth.json`。
6. GUI 和 CLI 都依赖 `CodexRateKit` 的共享模型与估算逻辑。

## 当前确认的推荐逻辑

- `UsageMonitor.State.switchRecommendation` 是当前 UI 推荐文案的单一事实源。
- 推荐分支只有四种：`syncing`、`stay`、`switchNow`、`noAvailable`。
- 当前分值大致由以下组合得出：
  - `min(primary, weekly) * 3.2`
  - `primary * 1.1`
  - `weekly * 0.45`
  - `reviewRemaining * 0.08`
  - 低余额惩罚 `-28`
  - 当前账号小幅加分 `+4`
- 如果要改推荐文案或推荐决策，优先同时看 `UsageMonitor.State` 和 `PopoverViewController` 的渲染逻辑。

## 当前确认的本地数据路径

- 根目录：`~/Library/Application Support/CodexRateWatcherNative/`
- 关键文件/目录：
  - `samples.json`
  - `profiles.json`
  - `auth-profiles/`
  - `auth-backups/`

## 当前确认的启动与验证方式

- 正式构建：
  - `./scripts/build_app.sh <version>`
  - 产物会落到 `dist/Codex Rate Watcher.app` 和 `dist/codex-rate`
- 正式启动：
  - `open 'dist/Codex Rate Watcher.app'`
- 调试窗口模式：
  - `swift run CodexRateWatcherNative -- --window`
- CLI 冒烟：
  - `swift run codex-rate status`
  - `swift run codex-rate status --json`
- 测试：
  - `swift test`

## 2026-03-20 当前快照

- 本地最新 tag 为 `v1.4.0`。
- 已实测 `./scripts/build_app.sh 1.4.0` 可以成功打出正式 `.app` 包。
- 当前 `.app` 打包逻辑完全在 `scripts/build_app.sh`，其中直接生成 `Info.plist` 并复制 release 二进制；不要假设有额外的 Xcode 打包配置。
- 当前 UI 代码使用 `PopoverViewController.swift` 中的 `LN` 设计 token；不要把旧的多列布局、`SurfacePalette` 或毛玻璃实现当成现状，除非先在代码里核实。

## 当前已知注意点

- release 构建目前会有少量编译 warning，主要在：
  - `Sources/codex-rate/main.swift`
  - `Sources/CodexRateWatcherNative/AppDelegate.swift`
  - `Sources/CodexRateWatcherNative/PopoverViewController.swift`
- 这些 warning 更像是清理项，不像功能 blocker，但如果顺手修，会是比较安全的 housekeeping。
- 如果改 CLI 的 JSON 输出，记得同时检查 `raycast-extension/` 的兼容性。
- 如果改 profile 切换或 auth 捕获逻辑，记得连带检查：
  - 当前 auth 备份是否还在
  - 孤儿快照回收是否还生效
  - auth 文件监听是否会触发重复刷新

## 给后续代理的建议

- UI 问题优先从 `PopoverViewController.swift` + `UsageMonitor.swift` 一起看，不要只改样式不改状态映射。
- 菜单栏行为问题优先看 `AppDelegate.swift`，尤其是 accessory 模式、popover 切换和右键菜单。
- 账号/认证问题优先看 `AuthStore.swift`、`Persistence.swift`、`AuthFileWatcher.swift`。
- 只要结论和当前代码不一致，就以代码为准，不要沿用旧记忆。
