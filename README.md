# Tick Momentum Burst EA

**Languages / زبان‌ها:** [English](README.md) · [فارسی](README_FA.md)

**Tick Momentum Burst + Cost-Aware Break-Even + Dynamic Trailing Stop** — an MQL5 Expert Advisor
that tests whether very short-term directional behaviour in the **MT5 tick stream** contains a
tradable momentum edge on CFD symbols (US30, US100, US500, XAUUSD, EURUSD, …).

> **CFD limitation (read first).** This EA measures *broker-provided* tick-price behaviour.
> For CFDs there is no central order flow. An UP tick is **not** "institutional buying" —
> it is just the broker's quote moving up. The project tests whether that behaviour has
> predictive value *after* spread, commission and slippage. The honest answer may be **NO**.

## Status

Research implementation, v1.00. Defaults are **initial research values, not optimized**.
No profitability is claimed. See `docs/RESEARCH_REPORT.md`.

## Layout

```text
MQL5/Experts/TickMomentumBurstEA.mq5      main EA (inputs, OnInit/OnTick/OnTradeTransaction)
MQL5/Include/TickMomentum/*.mqh           OOP modules (see Architecture below)
tests/mirror.py, tests/test_logic.py      Python mirror + unit tests (23 green, run on Linux)
tests/test_simulation.py                Tick-for-tick lifecycle simulation (8 scenarios green)
scripts/static_check.py                   MQL5 sanity checker (brace balance, safety tokens)
docs/                                     README(s), guides, research report
```

## Architecture

| Module | Responsibility |
|---|---|
| `CTickDataCollector` | Ring-buffer of last N ticks, mid-price UP/DOWN/NEUTRAL classification, `CopyTicks` backfill |
| `CMarketMetrics` | Directional ratio, displacement (pts), ticks/sec over window |
| `CMomentumDetector` | Multi-gate burst: ratio ∧ displacement ∧ tick-rate ∧ direction agreement |
| `CSignalEngine` | Burst + spread + position-limit + cooldown + risk-lock + abnormal-market gates |
| `CSymbolInfoCache` | Dynamic symbol props (digits, tick size/value, volume limits, stops/freeze) |
| `CMoneyMath` | `money = dist/tickSize*tickValue*vol` conversions, stops-level enforcement, tick snapping |
| `CCostCalculator` | Spread cost, estimated (pre-trade) vs actual (deal-history) commission, true BE prices |
| `CPositionSizer` | Fixed lot + optional risk-% sizing (v1.20, off by default) |
| `CTradeExecutor` | `CTrade` market orders, monetary SL/TP, re-anchor to fill, retcode checks |
| `CBreakEvenManager` | Moves SL to entry ± (round-trip commission + buffer) once covered; never fakes BE |
| `CTrailingStopManager` | Tightens only (BUY↑ / SELL↓), respects stops level, requires BE first |
| `CRiskManager` | Cooldown, max trades/day, consecutive-loss lock, daily-loss lock, abnormal-market cap |
| `CTradeJournal` | Per-trade record (entry metrics, MFE/MAE, exit reason) + optional CSV |
| `CStrategyController` | State machine + orchestration; position management **always runs first** on every tick |

State machine: `WAITING → SIGNAL → ORDER → OPEN → COST_COVERED → BE → TRAIL → (close) → COOLDOWN → WAITING`.
Restart-safe: on init the controller re-attaches to its own (symbol+magic) position.

## Quick start (Strategy Tester)

1. Copy `MQL5/` contents into your MT5 data folder, compile in MetaEditor (F7, 0 errors).
2. Tester: **Every tick based on real ticks**, symbol e.g. US30, real-tick date range.
3. Set commission in Tester inputs AND `InpCommissionPerLot` consistently.
4. Full procedure: `docs/BACKTEST_GUIDE.md`. Every input explained: `docs/INPUTS_GUIDE.md`.

## Commission model (estimated vs actual)

- **Estimated** (`InpCommissionPerLot`, one side per 1.0 lot; ×2 by default for round-trip)
  is used *before/during* the trade for BE/trigger math.
- **Actual** is read from deal history (`DEAL_COMMISSION`, both legs) when the trade closes
  and stored in the journal. The two are never mixed.

## Safety

No martingale / grid / averaging / recovery multipliers. Default max 1 position.
Spread filter, cooldown, daily-loss lock, consecutive-loss lock. Manages only its own
symbol+magic positions. See `docs/INPUTS_GUIDE.md` and `HANDOFF.md`.
