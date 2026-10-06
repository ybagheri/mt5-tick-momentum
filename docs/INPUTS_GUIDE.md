# Parameter Guide — Tick Momentum Burst EA v1.00

All defaults are **initial research values, explicitly NOT optimized**.

## Trading

| Input | Default | Meaning |
|---|---|---|
| `InpLotSize` | 0.01 | Fixed volume. Normalized to broker min/max/step; init fails if below minimum. |
| `InpSLMoney` | 1.0 | Initial stop as account-currency loss target (gross price move; net loss ≈ SL + costs). Converted via `money·tickSize/(tickValue·vol)`, then stops-level enforced and tick-snapped. |
| `InpTPMoney` | 2.0 | Initial take-profit target (≈1:2 gross R:R). Same conversion. |
| `InpMagicNumber` | 26061001 | EA manages **only** positions with this magic **and** the chart symbol. |
| `InpDeviationPoints` | 20 | Max slippage for `CTrade`. Tune per symbol (indices need more than FX). |
| `InpMaxPositions` | 1 | Simultaneous strategy positions. Keep 1 (no grid/averaging by design). |
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
| `InpTickWindow` | 50 | Rolling window length (ticks). |
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

## Protection

| Input | Default | Meaning |
|---|---|---|
| `InpCooldownSeconds` | 5 | No new entry after a close. Server-time measured. |
| `InpMaxTradesPerDay` | 50 | Runaway-trading fuse. |
| `InpMaxConsecutiveLosses` | 5 | Loss-streak lock (persists across days). |
| `InpMaxDailyLossMoney` | 10.0 | Net daily loss lock (resets daily), actual-commission basis. |

## Logging / journal

| Input | Default | Meaning |
|---|---|---|
| `InpLogLevel` | 3 | 0=OFF 1=ERROR 2=WARNING 3=INFO 4=DEBUG (per-tick only at DEBUG). |
| `InpEnableCSVJournal` | true | Write `InpCSVFile` in `MQL5/Files/`. |
| `InpCSVFile` | TickMomentumJournal.csv | Columns: close_time,symbol,dir,vol,entry,exit,sl0,tp0,spread_entry,est_comm,actual_comm,gross,net,mfe,mae,hold_s,ticks,ratio,disp_pts,tps,exit_reason,ticket. |
