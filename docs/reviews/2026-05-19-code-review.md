# 看盘侠 — 代码质量 Review

**日期**: 2026-05-19
**审视分支**: `feat/v0.3.0-toast-confirm-feedback` @ `63c7c0b`
**源码规模**: 26 Swift 文件，~3000 行；HoldingsView 395 行 / FundClient 244 行最大
**测试**: 0（无 XCTest target，无测试文件）

---

## 一、架构 — 7/10

清晰分层：

```
data/      HTTP clients (actor) + parser + Models
storage/   持久化 stores (@MainActor)
engine/    RefreshScheduler + FundStore + debug log
ui/        SwiftUI views + Theme + Toast/ConfirmDialog
FundPlugin 主类胶水
```

`@MainActor` 标在状态层 (FundStore / Watchlist / GoldPositionStore)，`actor` 标在网络客户端 (FundClient / GoldClient / ETFClient / SpotGoldClient / GoldKlineClient / GoldMinuteClient)。**并发模型一致**。

### 问题 1：store 持有 watchlist 但没转发 objectWillChange

`FundStore.swift:30` `let watchlist: Watchlist`。store 没 subscribe `watchlist.$funds` 转发到自己。watchlist 的 `@Published` 改动只对直接观察它的 view 生效。`HoldingsView` 直接 `store.watchlist.funds` 读能 work 是因为 SwiftUI 沿 @ObservedObject 链 propagation，但 store 上的 `totalMarketValue` / `count(for:)` 这类 computed 不会触发 store 自己的 objectWillChange。**结果**：watchlist add/remove 后，hero card 重算依赖下次 store.estimates 触发的 view update 顺带过来，时序边缘有 stale 风险。

**修法**：
```swift
init() {
    self.watchlist = Watchlist()
    watchlist.objectWillChange
        .sink { [weak self] in self?.objectWillChange.send() }
        .store(in: &cancellables)
}
```

### 问题 2：goldDailyBars / GoldRange 全链路 dead code

`Models.swift:181 GoldRange` + `FundStore.goldBars(for:)` + `GoldKlineClient.swift` 全部健在，但 `GoldView` 渲染的是 `goldMinuteLine`（分钟线），不再调 `goldBars(for:)`。整套日 K 线机制在 store 里循环 refresh，view 没 render。**删能少 200 行**。

---

## 二、状态管理 — 7/10

### 强项

- `FundStore.shared` 单例，view 全用 `@ObservedObject` 共享，一致
- `WatchlistFund.shares/costNav` Optional 设计 graceful 支持 watchlist-only 模式

### 问题 1：estimates 整本字典拷贝

`FundStore.swift:94-112` 每次 refresh 拷贝整本 dict → mutate → assign 回 `self.estimates`。同理 `goldQuotes`。N 只基金 O(N) 复制。对 10-50 只 OK，扩到 200 只 row diff 全量重算会 visible jank。

**修法**：单 entry update + `self.estimates[code] = ...` 直接 mutate，依赖 `@Published` 的 willSet/didSet 一次性发 signal。

### 问题 2：Watchlist init() 同步 load

`Watchlist.swift:18-26` init() 内同步 `Data(contentsOf: storeURL)` + JSON decode。watchlist.json 大到几 MB 会卡主线程。当前不是问题，但 ceiling 在那里。

---

## 三、并发安全 — 8/10

### 强项

- 所有 HTTP client 都标 `actor`，避免 URLSession 跨线程 hazard
- `@MainActor` 在 store 和 UI 控制器 (ToastController / ConfirmController)
- `Task { @MainActor in ... }` 在 plugin lifecycle 里跨域 hop 正确

### 🔴 BUG 1：Toast.swift:64 sleep 时长 truncate

```swift
try? await Task.sleep(nanoseconds: UInt64(self?.durationSeconds ?? 2.6) * 1_000_000_000)
```

`UInt64(2.6) == 2`（Double → UInt64 truncate）。乘 1_000_000_000 得 2_000_000_000 ns = **2.0s**，不是 `durationSeconds: Double = 2.6` 想要的 2.6s。Toast 比设计早 0.6s 消失。

**修法**：
```swift
let nanos = UInt64((self?.durationSeconds ?? 2.6) * 1_000_000_000)
try? await Task.sleep(nanoseconds: nanos)
```

这是 typo 级 bug，**v0.3.0 release 前必修**。

### 问题 2：ConfirmController 并发 ask() 没保护

`ConfirmDialog.swift:54-56`：若两个 caller 同时 await `ask()`，第一个 continuation 被 resume(false)，第二个 pending = req 覆盖。@MainActor 隔离让这 race 不会内存损坏，但语义上前者拿到一个"用户没操作"的 false。当前注释说"shouldn't normally happen"但没保证。**建议**：要么文档化要么改严格队列。

---

## 四、错误处理 — 5/10

### 🔴 问题 1：AddView 搜索失败 silent swallow

`AddView.swift:138`：
```swift
do { hits = try await FundClient.shared.search(q) }
catch { hits = [] }
```
用户搜东西网超时看到"未找到匹配的基金"。实际是 15s timeout。**P0 加 error toast**。

### 问题 2：GoldClient / SpotGoldClient errors silent degrade

`FundStore.swift:140` `if let s = await spot { self.spotGold = s }` — fetch 失败 spotGold 保持上一次值。用户看到 stale price 不知道。**建议**：连续 3 次失败 → footer 显示"网络异常"。

### 问题 3：FundDebugLog 写 `/tmp/fund-plugin.log` 无 rotation

`FundDebugLog.swift:14`：production 装机后每次 refresh 都追加文件。macOS `/tmp` 不会自动清。size cap 缺。**建议**：写到 `~/Library/Logs/Mio Island/fund-plugin.log` + 10MB rotate；或只在 DEBUG flag 启用。

---

## 五、网络层 — 8/10

### 强项

- 真懂 Sina/Eastmoney quirks：GB18030 编码、Referer 校验、JSONP `jsonpgz(...)` 包装、cache-buster `?rt=ts`
- `withTaskGroup` 并行 fetch，单 endpoint 死不拖累全 panel
- 全 HTTPS（FundClient.estimate URL 也是 https）

### 问题 1：timeout 不一致

| Client | request / resource |
|---|---|
| FundClient | 15s / 25s |
| GoldClient | 6s / 12s |
| SpotGoldClient | 6s / 12s |
| ETFClient | 6s / 12s |
| GoldKlineClient | 8s / 15s |
| GoldMinuteClient | 8s / 15s |

混合超时本身 OK，但 cold-start 时第一个 TLS 握手往往压在 fundgz（FundClient 15s 是对的）。其它 client 沿用 6s 在 cold start 会被掐。**建议**：全 client 统一到 `URLSessionConfiguration.timeoutIntervalForRequest = 12` baseline。

### 问题 2：没 retry / 没 exponential backoff

fetch 失败 → 等下次 cadence (60s/30min) → 再失败。冷启动 3 分钟没数据 = 用户走人。**建议**：first refresh 失败 → 5s 后再试一次（不算正常 cadence）。

### 🔴 问题 3：ETFClient.isETFCode 路由过宽

`EtfClient.swift:71-72`：
```swift
case 510...599, 150...199:
    return true
```

`150...199` 覆盖深市 159 (ETF) **但也覆盖 161/162/163 (LOF)** 和 167 (LOF) — LOF 走 OTC 净值估值不是分笔交易，被路由到 ETFClient 会失败/取错数据。**修法**：白名单收紧到 159, 165, 188, 159001-159999 实际是 ETF 的码段。

---

## 六、UI 层 — 7/10

### 强项

- `Theme.swift` 集中色彩 token，all views 引用
- 一致的 RoundedRectangle + overlay04 + 0.5 stroke 风格
- `Color.upDown(value)` helper 抽象红涨绿跌
- `SparkLine.swift` 自绘 SVG-equivalent，零依赖

### 问题 1：watchlist.funds.map(\.code) 当 animation value

`HoldingsView.swift:131`：
```swift
.animation(.spring(...), value: store.watchlist.funds.map(\.code))
```
每次 render 都构造新 `[String]`。性能上无害但 inefficient。**建议**：Watchlist 加 `var codeFingerprint: Int { funds.reduce(0) { $0 &+ $1.code.hashValue } }`。

### 问题 2：没 reorder UI

`Watchlist.swift:56` 提供 `move(from:to:)` API，但没 view 调用。drag-reorder 没实现。**P1**。

---

## 七、安全 — 7/10

### 强项

- 全 HTTPS
- 没存敏感 token / 用户登录 — 100% 本地
- watchlist.json 写到 user-domain Application Support，不需要 entitlement
- `codesign --force --deep --sign -` ad-hoc 签名 OK

### 问题 1：User-Agent "Mozilla/5.0"

短期 OK，但上架后用户激增被识别为 bot 是 risk。**建议**：UA 改成 `MioIsland-FundPlugin/0.3.0 (...)` —— 被 ban 时是定向不是误伤。

### 问题 2：没 rate limit

`ExpandedView.onAppear` trigger refresh，用户频繁 show/hide 刘海 panel 会蹬一波请求。**建议**：onAppear 检查 `lastFundRefresh < 30s` 就跳过。

---

## 八、测试 — 0/10

**No tests at all**。HANDOFF.md 提到 `/tmp/test-fund-clients.swift` 单文件 smoke test 但不在 repo 里。

**v1 必须有的**：

| 文件 | 测试场景 |
|---|---|
| `SinaQuoteParser` | GB18030 sample fixtures × 6 source（COMEX/London/SHFE/AU9999/sh/sz ETF）|
| `ETFClient.isETFCode` | 边界码：510, 512, 518, 159, 161 (LOF), 167 (LOF), 588 |
| `FundClient` JSONP 解析 | happy / `jsonpgz();` empty / 非 UTF-8 malformed |
| `Watchlist` save/load roundtrip | + 异常磁盘 atomic 写 |
| `RefreshScheduler.isAShareTradeHour` | 09:29 / 09:30 / 11:30 / 11:31 / 13:00 / 15:00 / 周末 |

---

## 九、Code smell 汇总

| 文件:行 | 问题 | 优先级 | 修复行数 |
|---|---|---|---|
| `Toast.swift:64` | `UInt64(2.6)` truncate，toast 早 0.6s 消失 | 🔴 P0 | 2 |
| `AddView.swift:138` | 搜索失败 swallow，没 toast | 🔴 P0 | 5 |
| `EtfClient.swift:71` | 150-199 路由 ETF 把 LOF 误收 | 🔴 P0 | 5 |
| `FundStore.swift:160-163` + `Models.swift:181` + `GoldKlineClient.swift` | 日 K 线 dead code | 🟡 P1 | 删 ~200 |
| `Watchlist.swift:78` | init 同步 load 大文件 | 🟡 P1 | 异步迁移 |
| `FundDebugLog.swift` | 写 `/tmp` 无 rotation | 🟡 P1 | 移路径 + size cap |
| `HoldingsView.swift:131` | map(\.code) 每次 render 跑 | 🟢 P2 | 加 fingerprint |
| 全 repo | 0 tests | 🟡 P1 | 加 XCTest target |
| `FundStore.swift:30` | watchlist objectWillChange 未转发 | 🟢 P2 | 5 |

---

## 十、总评

代码质量 **7/10** — 架构清晰、并发模型一致、网络层懂中国数据源。

**主要短板**：
1. **测试覆盖 = 0** —— 上架后崩了不知道哪坏
2. **Toast.swift:64 是 typo 级 bug**（UInt64 cast 数值常量）— 必修
3. **dead code 还在** — GoldRange / goldDailyBars / GoldKlineClient 没人用了
4. **ETF 码段路由把 LOF 误收** — 用户体验直接坏
5. **silent network failures** — 没用户可见信号

修完 P0 三项 + 加最小测试集（5 个 fixture），code quality 能拉到 9/10。
