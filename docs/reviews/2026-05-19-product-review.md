# 看盘侠 — 产品 Review

**日期**: 2026-05-19
**审视版本**: v0.3.0 (`feat/v0.3.0-toast-confirm-feedback` @ `63c7c0b`)
**装机验证**: `~/.config/codeisland/plugins/fund.bundle` v0.3.0 build 3 已在 Mio Island 3.0.0 运行

---

## 一、核心价值主张

| 维度 | 评分 | 说明 |
|---|---|---|
| 差异化 | 8/10 | 基金 + 黄金跨品类合一，刘海常驻，无服务端依赖 |
| 价值密度 | 7/10 | 持仓 P&L 实时算 + 黄金分钟线 + 多市场对比 pill 一屏内 |
| 上手摩擦 | 8/10 | 持仓 shares/cost 可不填，graceful 降级到 watchlist 模式 |

### 强项

1. **跨品类合一** — 市面上养基宝只看基金，跟谁学只看金价。同时看一屏没几个。
2. **零服务端架构** — 数据全走天天/东方财富/新浪公开端点，永远不会因为后端关停就死。代价：没法做服务端聚合或推送。
3. **持仓非强制** — `WatchlistFund.shares` / `costNav` 都是 `Double?`，没填也能用 watchlist 模式（`HoldingsView.swift:142-175` hero card 自动 fallback "X 只基金"）。降低 onboarding 摩擦。

### 弱项

1. **README pricing 是空头支票** — README.md:98-105 写了 ¥49 once / ¥99 yearly 的 Pro tier 表格 + AI 解盘，v0.3.0 全免费、license 系统不存在。要么删定价段，要么尽快做 license gating —— 否则上架审核员看到会困惑，用户看到会觉得"骗"。
2. **"看盘侠"名字 vs 实际功能 mismatch** — 名字暗示"看 K 线深度"（同花顺/雪球级别），实际是基金估值 + 金价。第一次打开的用户期待会被拉低。
3. **黄金为什么挂在基金 tracker 里？** — 概念上不重叠。如果用户只想看金价不看基金，"持仓 tab + 添加 tab" 都是 dead weight。

---

## 二、UX 流程完整度

### 走通 happy path（v0.3.0 新增反馈环）

1. 持仓空状态 → 点 "去添加" → tab 切到添加 ✓
2. 搜 "易方达蓝筹" → tap + → 绿 toast「已添加「xxx」到自选」✓（v0.3 新）
3. 回持仓 tab → 看见 row → tap 展开 PositionEditor → 填份额+成本 → 绿 toast ✓
4. Hero card 自动算 总市值 / 今日盈亏 / 累计盈亏 / 收益率 ✓
5. hover row → 出 ✕ → tap → 红色 ConfirmDialog → 确认/取消 ✓（v0.3 新，防误删）

### 断点与边缘 case

1. **搜索失败 silent swallow** — `AddView.swift:138`
   ```swift
   do { hits = try await FundClient.shared.search(q) }
   catch { hits = [] }
   ```
   用户搜 "易方达" 网超时，看到"未找到匹配的基金"。实际是 15s 超时不是没结果。**P0**：error path 加错误 toast。
2. **没"搜索历史"** — 用户搜过一次就丢，下次重启又要打字。`AddView` state 完全 ephemeral。**P1**：5 个 recent searches 就够。
3. **黄金 K 线产品意图不明** — `GoldView` 实际渲染的是 `goldMinuteLine`（当日分钟线），但 README 还在讲"1月/3月/1年/全部" 日 K 切换，`Models.swift:181 GoldRange` enum 也还在。两套数据流并存只渲染一套。要么把日 K 切换的 UI 找回来，要么砍 dead code。
4. **"添加" tab 已添加 row** — `SearchRow.swift:182 .disabled(alreadyAdded)` 与 v0.3 新加的"再点弹 info toast"逻辑冲突 — disabled 状态会吃掉 tap，info toast 永远不触发。需 cleanup。
5. **黄金持仓 vs 基金持仓 UX 不一致** — 基金 PositionEditor 在 row 下方展开 (`HoldingsView.swift:99`)；黄金 GoldPositionCard 在 card 内 toggle (`GoldPositionCard.swift:32-43`)。同一概念两种交互。
6. **footer "更新于 X 分前"误读** — `ExpandedView.swift:210` 显示上次刷新时间，但盘后实际 cadence 是 30 min。用户看到"更新于 25 分前"会以为坏了。**建议**：盘后改成"下次刷新 N 分后"或"盘后空闲"。

---

## 三、信息架构

| 强项 | 弱项 |
|---|---|
| 持仓 column header（今日/累计）— 一眼看清两列含义 | "添加"tab 默认页写"数据源: 东方财富 fund.eastmoney.com" — 偏 dev-y |
| Hero card graceful 降级（"X 只基金"）| "国内金价 AU9999.SGE" — 普通用户不认这 ticker |
| 黄金 tab 一屏放下：实时 + 分钟线 + 持仓 + 伦敦/纽约 pill | 没"全局 status"footer 字段，refresh 失败/网异常没 surface |
| `.upDown(value)` helper 一致的中国式红涨绿跌 | hero card 上 hover 没 affordance（用户不知道 row 可点） |

---

## 四、与竞品对比

| | 看盘侠 | 养基宝 | 蛋卷基金 | 同花顺 Mac |
|---|---|---|---|---|
| 桌面常驻 | ✅ 刘海 | ❌ App | ❌ App | ❌ App |
| 隐私（无登录无服务端）| ✅ | ❌ | ❌ | ❌ |
| 基金 + 黄金一屏 | ✅ | ❌ | ❌ | ⚠️ 不同模块 |
| 持仓 P&L | ✅ | ✅ | ✅ | ✅ |
| AI 解盘 | ❌（计划）| ✅ | ❌ | ⚠️ |
| K 线深度 | ⚠️ 分钟线 | ❌ | ❌ | ✅✅ |
| 多账户 | ❌ | ✅ | ✅ | ✅ |
| ETF 实时 | ✅ | ⚠️ | ⚠️ | ✅ |

**差异化定位**：刘海 + 跨品类 + 隐私。瞄准"已经知道自己持仓、不想再装一个 app 占菜单栏"的轻量用户。**不要**对标同花顺做深度。

---

## 五、上架前必修（P0）

| # | 项 | 文件 / 位置 |
|---|---|---|
| 1 | README pricing 删掉或改成"Pro tier 计划中" | `README.md:98-105` |
| 2 | 搜索失败要弹 error toast | `AddView.swift:138` catch 块 |
| 3 | 删 dead K 线代码 OR 把日 K 切换 UI 加回来 | `GoldKlineClient` / `goldDailyBars` / `GoldRange` |
| 4 | footer 文案盘后改成"下次刷新 N 分后" | `ExpandedView.swift:209-213` |
| 5 | SearchRow.disabled vs info toast 二选一 | `AddView.swift:182` |

---

## 六、建议加（P1）

1. **个股 quote tab** — 已有 ETFClient (Sina sh/sz endpoint)，扩展 A 股股票几乎就是 prefix 路由
2. **搜索历史** — 5 个 recent searches
3. **设置面板** — refresh interval 可调、tab 显示偏好（隐藏黄金？）
4. **每日 P&L 累计 chart** — 持仓 hero data 存 SQLite，画周线趋势（这是 Pro tier 的真正钩子，比 AI 解盘更落地）
5. **drag-reorder 持仓** — Watchlist 已经有 `move(from:to:)` API，view 没用

---

## 七、建议砍（P-1）

1. **黄金 K 线 1月/3月/1年/全部 切换** — 代码留着没用上；产品上"长线看金"跟 quick-glance 体验不匹配
2. **MioIsland 主题适配** — HANDOFF.md 自己说没做。固定 lime/gold 配色其实视觉更统一，不要补

---

## 八、总评

| 问 | 答 |
|---|---|
| v0.3.0 上架免费版？ | **是** |
| v0.3.0 上架收钱版？ | **否**（pricing 是空头支票，AI 解盘没影）|
| 上架前必修项数？ | 5 个（见上）|
| 最大产品风险 | 名字"看盘侠" vs 实际功能 mismatch，第一印象拉低 |
| 最大产品亮点 | 跨品类 + 刘海常驻 + 隐私三合一 |

**优先级 sequence**：修 P0 五项 → tag v0.3.0 → 上架免费 → 做"个股 tab"和"P&L 趋势"作为 Pro 钩子 → 再谈付费。
