# Parameter Guide — Tick Momentum Burst EA v1.40

All defaults are **initial research values, explicitly NOT optimized**.

Inputs are collected into a single `TMBConfig` struct (`TMBConfig::SetDefaults()`
holds the canonical defaults, mirrored by the `input` declarations below) and handed
to `CStrategyController::Configure`. `scripts/static_check.py` fails if any input is
left unwired.

## Trading

| Input | Default | Meaning |
|---|---|---|
| `InpLotSize` | 0.01 | Fixed volume. Normalized to broker min/max/step; init fails if below minimum. |
| `InpSLMoney` | 1.0 | Initial stop as account-currency loss target (gross price move; net loss ≈ SL + costs). Converted via `money·tickSize/(tickValue·vol)`, then stops-level enforced and tick-snapped. |
| `InpTPMoney` | 2.0 | Initial take-profit target (≈1:2 gross R:R). Same conversion. |
| `InpMagicNumber` | 26061001 | EA manages **only** positions with this magic **and** the chart symbol. |
| `InpDeviationPoints` | 20 | Max slippage for `CTrade`. Tune per symbol (indices need more than FX). |
| `InpMaxPositions` | 1 | Must be **1**. The pipeline manages a single ticket (no grid/averaging by design); any other value fails `OnInit` instead of being silently ignored. |
| `InpTPMode` | 0 | 0=`FIXED_TP` · 1=`TRAILING_ONLY` (no fixed TP, requires trailing ON) · 2=`HYBRID` (fixed TP + trailing). |

## Commission

| Input | Default | Meaning |
|---|---|---|
| `InpCommissionPerLot` | 6.0 | Estimated **one-side** commission per 1.0 lot in account currency. Pre-trade estimate only. |
| `InpCommissionDoubledRT` | true | If true, round-trip estimate = 2 × one side (open + close legs). Conservative and correct for per-deal commission. |

Actual commission is read from `DEAL_COMMISSION` (both legs) on close and journaled separately.

## Tick momentum

| Input | Default | Meaning |
|---|---|---|
| `InpTickWindow` | 50 | Rolling window length (ticks, min 5). Metrics are only `ready` once the window is **full** — a partial window never produces a signal, so backfill plus the first live ticks must fill it. |
| `InpMinimumDirectionalRatio` | 0.70 | `max(up,down)/(up+down)` within [0.5, 1]. |
| `InpMinimumPriceMovePoints` | 10 | Min absolute displacement `|latest.mid − oldest.mid|` in points. |
| `InpMinimumTicksPerSecond` | 1.0 | Min `(n−1)/windowSeconds`. Irregular arrival handled via actual timestamps. |
| `InpMaximumTicksPerSecond` | 0.0 | Abnormal-rate veto (0 = off). |
| `InpMaximumDisplacementPoints` | 0 | Abnormal-jump veto (0 = off). |
| `InpMaximumWindowSeconds` | 0 | Stale-window veto (0 = off). |

## Spread

| Input | Default | Meaning |
|---|---|---|
| `InpMaxSpreadPoints` | 100 | New entries blocked above this. Management of open positions continues. |

## Break-even

| Input | Default | Meaning |
|---|---|---|
| `InpEnableBreakEven` | true | Cost-aware BE on/off. |
| `InpBreakEvenBufferMoney` | 0.02 | Extra net-profit target locked at BE (account $). |

True BE: BUY `BE_bid = entryAsk + (RTcommission + buffer)·tickSize/(tickValue·vol)`;
SELL mirrored. Trigger = favourable move ≥ that distance. Never moves SL to raw entry.

## Trailing

| Input | Default | Meaning |
|---|---|---|
| `InpEnableTrailing` | true | Trailing on/off (activates only after BE). |
| `InpTrailingDistanceMoney` | 0.50 | Trail distance in account $, converted to price. BUY: SL only up. SELL: SL only down. |

## Risk-based sizing (EA v1.10+, off by default)

| Input | Default | Meaning |
|---|---|---|
| `InpUseRiskSizing` | false | `false` = fixed lot. `true` = volume scaled so the SL money amount equals equity × percent. |
| `InpRiskPercent` | 0.5 | Risk per trade as % of **equity** (validated in (0, 10]). This becomes the effective SL money. |
| `InpRiskMaxLot` | 1.0 | Hard cap for the risk-scaled volume (broker max also applies). |

Mechanics: `k = (equity × pct/100) / InpSLMoney`, `V = InpLotSize × k`
(normalized, capped). SL/TP/BE-buffer/trailing **money** values are all multiplied
by the same `k`, so every price distance is identical to fixed-lot geometry — only
money outcomes scale. If caps bind, the journal logs the effective SL money and the
per-trade `risk_k` column records `k`. If the scaled volume falls below the broker
minimum, the signal is skipped (no trade). Fixed mode is exactly `k = 1`.
Use the tester with real equity curves; commission estimates scale automatically
with the larger volume via `EstimateRoundTripCommission`.

## Context / volatility filter (EA v1.30+, all off by default)

The tick stream stays the primary signal. When enabled, closed-bar candles add an
extra veto (never a trigger). Reads use the last **closed** bar (no intra-bar repaint).

| Input | Default | Meaning |
|---|---|---|
| `InpUseContextTrend` | false | `true` = BUY only above EMA, SELL only below EMA. |
| `InpContextTimeframe` | H1 | Candle timeframe for context. |
| `InpContextMAPeriod` | 50 | EMA period (≥ 2). |
| `InpUseVolatilityFilter` | false | `true` = block entries while ATR > max. |
| `InpATRPeriod` | 14 | ATR period (≥ 2). |
| `InpMaxATRPoints` | 0.0 | Max ATR in points; must be > 0 when the vol filter is on. |

Fail-safe: if indicator data is unavailable (handles invalid, history missing),
entries are **blocked** with reason `CTX_NO_DATA` / `VOLATILITY` / `CONTEXT_FILTER`
while management of open positions continues. Recommended test order: trend-only,
then vol-cap-only, then both — compare against the unfiltered baseline in the CSV.

## Protection

| Input | Default | Meaning |
|---|---|---|
| `InpCooldownSeconds` | 5 | No new entry after a close. Server-time measured. |
| `InpMaxTradesPerDay` | 50 | Runaway-trading fuse. |
| `InpMaxConsecutiveLosses` | 5 | Loss-streak lock. Cleared on a new server day when `InpResetConsecOnNewDay` is true. |
| `InpMaxDailyLossMoney` | 10.0 | Net daily loss lock (resets daily), actual-commission basis. |
| `InpResetConsecOnNewDay` | true | On a new server day: reset daily counters (`trades`, `dailyNet`), release the daily/max-trades lock and — when true — reset the loss streak and release its lock. Set false to make a consecutive-loss lock persist until the EA restarts. |

A trade counts once, on **open**. Closing updates P/L, the streak and the cooldown
only, so a repeated close callback cannot inflate `InpMaxTradesPerDay` or hand out a
second cooldown.

## Logging / journal

| Input | Default | Meaning |
|---|---|---|
| `InpLogLevel` | 3 | 0=OFF 1=ERROR 2=WARNING 3=INFO 4=DEBUG (per-tick only at DEBUG). |
| `InpEnableCSVJournal` | true | Write `InpCSVFile` in `MQL5/Files/`. |
| `InpCSVFile` | TickMomentumJournal.csv | Columns: close_time,symbol,dir,vol,entry,exit,sl0,tp0,spread_entry,est_comm,actual_comm,gross,net,mfe,mae,hold_s,ticks,ratio,disp_pts,tps,exit_reason,ticket,risk_k. |

The header is written **only when the file is new or empty**, so restarts append to
the existing journal instead of truncating it. Exit reason is classified from the
trade record: a fill at/beyond the placed TP is `TAKE_PROFIT` (checked first, matched
directionally so gaps and tick granularity still count), then `TRAILING_STOP`, then
`BREAK_EVEN`, then `STOP_LOSS`.

## Tester criterion

`OnTester()` returns this EA's net profit on this symbol, summed from deal history
(`DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION`) for the configured magic — so
optimization ranks actual net result rather than a constant zero.
