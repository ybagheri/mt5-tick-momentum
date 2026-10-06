# Backtesting Guide — Tick Momentum Burst EA

Tick logic is tester-safe **only** in real-tick mode. Candle modes (`OHLC`, `Open prices`)
fabricate ticks and will produce meaningless signals.

## Required tester settings

1. Model: **Every tick based on real ticks**.
2. Date range with genuine tick history (check broker symbol tick availability first).
3. Commission: set Tester "Commission" AND match `InpCommissionPerLot` to the same assumption.
4. Run one symbol per test (EA trades the chart symbol only).

## Functional verification (Test A — short period)

Use 1–3 days of real ticks, `InpLogLevel=4` (DEBUG), visual mode:

- [ ] Signals only when burst gates pass (log shows reject reasons otherwise).
- [ ] Spread spike → `Reject: SPREAD`, no entry.
- [ ] Cost covered → `BE applied #…` at true BE (not entry price).
- [ ] Trailing → BUY SL strictly non-decreasing, SELL strictly non-increasing.
- [ ] While open → further signals rejected (`POSITION_LIMIT`).
- [ ] After close → `COOLDOWN` rejects immediate re-entry.
- [ ] Restart EA mid-position → "Reattached to existing position", management resumes.

## Sensitivity battery (Tests B–H)

| Test | Vary | Expectation to record |
|---|---|---|
| B | 4–12 weeks real ticks | Baseline net, PF, win rate, drawdown, trade count |
| C | US30 / US100 / XAUUSD / EURUSD | Per-symbol expectancy (different tick size/value!) |
| D | `InpMaxSpreadPoints` tight vs loose | Fewer, possibly better-quality trades when tight |
| E | Commission 0 / 6 / 12 | Expectancy decay with costs (report gross AND net) |
| F | `InpTickWindow` 20 / 50 / 100 | Signal count vs quality trade-off |
| G | `InpTrailingDistanceMoney` 0.25 / 0.50 / 1.00 | Win-rate vs payoff trade-off |
| H | `InpTPMode` 0 vs 1 vs 2 | Fixed TP vs trailing-only vs hybrid |

## Metrics to report (every run)

Net profit · profit factor · expected payoff · win rate · avg win/loss ·
max drawdown · recovery factor · trade count · avg holding time ·
max consecutive losses — **before and after costs** where separable.

## Optimization discipline (see also RESEARCH_REPORT)

1. Verify function first (Test A), then scan **one parameter at a time**, coarse grid.
2. Keep the core set small: `TickWindow, MinRatio, MinMove, MinTps, MaxSpread, SL, TP, BEbuffer, TrailDist, Cooldown`.
3. Split data: **in-sample → validation → out-of-sample**. Judge on OOS, not the best IS peak.
4. < ~30 trades per configuration = noise, not signal. Demand consistency across symbols/periods.
