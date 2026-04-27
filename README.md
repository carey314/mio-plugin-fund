# 看盘侠 — Fund & Gold Tracker for MioIsland

Real-time OTC fund and gold tracker for the macOS notch. Built as a
native `.bundle` plugin for [MioIsland](https://github.com/MioMioOS/MioIsland).

## Features

### 持仓 (Holdings)
- Live intraday fund estimates (~1 min granularity from 天天基金).
- Hero card with 总市值 / 今日盈亏 / 累计盈亏 / 收益率 — only computed
  for funds where you've filled in shares + cost basis.
- Per-fund row with name, code, latest NAV, day rate %, day ¥ P&L.
- Click any row to inline-edit shares + cost basis (or clear).

### 黄金 (Gold)
- Realtime SHFE 沪金 quote (RMB/g) as the primary chart.
- Daily K-line with 1月 / 3月 / 1年 / 全部 range tabs.
- Reference cards for 伦敦金 (XAU/USD) and 纽约金 (COMEX GC) with
  realtime price + day change.
- Historical chart back to 2008.

### 添加 (Add)
- Search 26,000+ public funds by code, name, or pinyin (东方财富 suggest API).
- Category-coded chips (ETF / 指数 / 股票 / 混合 / 债券 / QDII / etc).
- Already-added state with checkmark.

## Data sources (no API keys, no Python, no servers)

| Endpoint | Provider | Format |
|---|---|---|
| `fundsuggest.eastmoney.com/.../FundSearchAPI.ashx` | 东方财富 | JSON |
| `fundgz.1234567.com.cn/js/{code}.js` | 天天基金 | JSONP |
| `api.fund.eastmoney.com/f10/lsjz` | 东方财富 | JSON |
| `hq.sinajs.cn/list={symbol}` | 新浪财经 | CSV (GB18030) |
| `stock2.finance.sina.com.cn/.../IndexService.getInnerFuturesDailyKLine` | 新浪财经 | JSON array |

All endpoints are 10+ years old, used by every Chinese fintech app. No auth.

## Install

### From source

```bash
git clone <this repo>
cd mio-plugin-fund
./build.sh install
# Restart Mio Island (Cmd+Q + reopen)
```

### From marketplace

(After release: install via miomio.chat plugin store.)

## Development

```bash
./build.sh           # produce build/fund.bundle + build/fund.zip
./build.sh install   # build + copy to ~/.config/codeisland/plugins/
```

### Project structure

```
Sources/
├── MioPlugin.swift             # protocol (verbatim from host)
├── FundPlugin.swift            # principal class
├── data/
│   ├── Models.swift            # WatchlistFund, FundEstimate, GoldQuote, …
│   ├── FundClient.swift        # search + estimate + history
│   ├── GoldClient.swift        # 4 realtime gold sources
│   ├── GoldKlineClient.swift   # daily K-line history
│   └── SinaQuoteParser.swift   # GB18030 → GoldQuote parser
├── storage/
│   └── Watchlist.swift         # persisted JSON watchlist + positions
├── engine/
│   ├── RefreshScheduler.swift  # trade-hour-aware refresh cadence
│   └── FundStore.swift         # @MainActor state surface
└── ui/
    ├── Theme.swift             # design tokens (lime / gold / red-up / green-down)
    ├── ExpandedView.swift      # 380×540 panel, 3-tab strip + footer
    ├── HeaderSlotView.swift    # 20×20 notch icon
    ├── HoldingsView.swift      # 持仓 tab
    ├── GoldView.swift          # 黄金 tab
    ├── AddView.swift           # 添加 tab
    ├── PositionEditor.swift    # inline shares + cost form
    └── SparkLine.swift         # SVG-equivalent line chart
```

### Refresh cadence

| Tier | When | Interval |
|---|---|---|
| Funds intraday | 09:30-11:30, 13:00-15:00 (CST, Mon-Fri) | 60s |
| Funds idle | Otherwise | 30 min |
| Gold | 24/7 | 30s |
| Gold K-line history | On launch + manual refresh | — |

## Pricing (planned)

| Tier | Content |
|---|---|
| Free | 3 funds, daily NAV only, no gold, no AI |
| Pro (¥49 once / ¥99 yearly) | Unlimited watchlist, intraday estimates, gold panel, AI 解盘 |

Not enforced yet — v0.2 is the UI shell. Paid gating goes in v0.3.

## License

MIT — see [LICENSE](LICENSE).
