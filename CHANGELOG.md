# Changelog

## [1.40] — 2026-10-09 — Correctness pass (code review driven)

### Fixed (behavioural bugs)
- **Trades were counted twice per day**: `NotifyOpen` and `NotifyClose` both did
  `tradesToday++`, so `InpMaxTradesPerDay` allowed only half the intended number.
  Counting now happens on **open** only; close updates P/L, streak and cooldown.
- **A close without a journal record silently reset risk state**: net was `0.0`,
  which awarded a phantom breakeven (clearing the loss streak) and a free cooldown.
  Net is now always `gross − actual commission` from deal history, independent of the
  journal; a missing record logs a warning instead of corrupting the streak.
- **Partial tick windows could trigger entries**: `CMarketMetrics` reported `ready`
  with as few as 2 ticks, unlike the reference simulation. Metrics now require a
  **full** window (`InpTickWindow`) before any gate is evaluated.
- **Exit reasons were wrong**: `ClassifyExit` only looked at the BE flag, so a real
  TP fill after BE was journalled as `TRAILING_STOP`. Reason is now derived from the
  trade record (placed TP → trailing → BE → SL), matched directionally so gap-through
  fills and tick granularity still classify correctly.
- **Journal CSV was truncated on every init** (`FILE_WRITE` rewrite) and appended
  without `FILE_CREATE`. The header is now written only for a new/empty file.
- **Inconsistent stops-level margin**: `EnforceMinStopDistance` added a point on top
  of a `StopsLevelPrice()` that already added one (2 points vs 1 elsewhere). One
  source of truth now: `(stopsLevel + 1) × point`, with a matching `FreezeLevelPrice`.
- **Duplicate ticks polluted the window**: `OnTick` can fire repeatedly for the same
  tick. Duplicates are detected (same `time_msc`/bid/ask) and skipped for metrics and
  entries, while position management still runs on every tick.
- **Risk-scaled volumes below the broker minimum were silently lifted** to the
  minimum by `NormalizeVolume`. The pre-normalized target is now checked, so such a
  signal is skipped (matching the documented intent and the Python mirror).

### Added
- `InpResetConsecOnNewDay` (default true): the consecutive-loss lock and streak now
  clear on a new server day instead of persisting until the EA restarts.
- `OnTester()` returns real net profit from deal history (magic + symbol filtered)
  instead of a constant `0.0`, so optimization ranks actual results.
- `MQL5/Include/TickMomentum/Enums.mqh`: shared `ENUM_TMB_STATE` / `ENUM_TMB_TP_MODE`
  (`OpenMarket` now takes a typed TP mode instead of a bare `int`).
- `TMBConfig` struct: the 30-argument `Configure(...)` call is replaced by one struct
  with `SetDefaults()` as the single documented source of defaults.
- Validation: max positions must be 1 (was silently ignored), spread/cooldown
  non-negative, `FIXED` mode requires a positive TP money, context indicator warm-up
  is reported at init.

### Changed
- Structs holding `string` no longer use `ZeroMemory` (`TBBurstResult`, `TBSignal`,
  `TBOpenResult`, `TMBTradeRecord`, `TMBRiskVolume`) — they expose `Reset()`.
- `CTradeJournal::OnTickInTrade` snapshots the live SL and BE/trailing state so
  classification is correct even when the close arrives between ticks.
- `CTradeExecutor::ReanchorSLTPToFill` skips the modify when levels already match,
  and logs failures.
- `CTickDataCollector`: ring iteration via `At(i)`/`IsFull()` instead of copying the
  whole window every tick; `Backfill` hoists the spread lookup out of its loop; tick
  struct drops unused duplicated timestamps.
- `CMarketContextFilter`: one shared `Allowed()` gate instead of duplicated
  buy/sell logic; `BreakEven`/`Trailing` bail out when the symbol cache is invalid.
- `CRiskManager`: lock reasons combine instead of overwriting, and warnings log only
  on transition (no per-tick noise). `ResetCounters()` added.
- `scripts/static_check.py` rewritten: resolves include targets, checks unique include
  guards, per-line martingale/grid patterns (the old `"never" in blob` guard made the
  check permanently inert), verifies every input is wired into `TMBConfig`, and
  rejects `ZeroMemory` on string-bearing structs.
- Python mirror parity: `notify_open`/`notify_close` day handling,
  `classify_exit`, `metrics_ready` added; tests 23 → 40 logic assertions.

## [1.30] — 2026-10-07 — Optional candle context / volatility filter
### Added
- `CMarketContextFilter`: closed-bar EMA trend alignment + ATR volatility cap,
  all off by default; tick stream remains the primary signal, candles only veto.
- Fail-safe block (`CTX_NO_DATA`) when indicator data is missing; handles released
  in `OnDeinit`; param validation in `Configure`.
- `tests/test_context_filter.py`: 14/14 green (alignment both sides, fail-safe,
  ATR cap, disabled passthrough, vol-only mode).

## [1.20] — 2026-10-07 — Risk-based position sizing
### Added
- `InpUseRiskSizing / InpRiskPercent / InpRiskMaxLot`: optional risk-% mode.
  `V = lot × (equity×pct/100) / SLMoney`, all money targets scaled by the same `k`
  so price geometry is unchanged; caps logged, sub-minimum volumes skip the trade.
- Per-trade effective BE/trailing overrides (`SetEffectiveBuffer/Distance`,
  cleared on close); `risk_k` column in CSV journal.
- `tests/test_risk_sizing.py`: 9/9 green (volume/k math, geometry invariance,
  caps, below-min block, fallbacks).

## [1.10] — 2026-10-07 — Farsi docs + lifecycle simulation ("next phase")
### Added
- `README_FA.md`: full Persian translation; language links in `README.md`.
- `tests/test_simulation.py`: tick-for-tick pipeline mirror, 8/8 scenarios green
  (BUY/SELL TP, spread veto, crash SL, no second entry under 34 bursts, cooldown,
  consec-loss lock, flat-market silence).
### Notes
- MetaEditor compile + Strategy Tester runs remain impossible on this Linux host
  (no sudo/wine, 2.4 GB disk); documented as the next terminal-side step.
- Simulation finding: entries trigger a few ticks into the burst window, so
  continuation quality (not detection speed) decides trades; post-crash
  counter-bursts are legitimate opposite signals (see RESEARCH_REPORT).

## [1.00] — 2026-10-06 — Full implementation, Phases 1–10

### Added
- `TickMomentumBurstEA.mq5`: inputs, `OnInit/OnTick/OnDeinit/OnTradeTransaction`,
  fill re-anchoring, restart re-attach, TP modes (FIXED / TRAILING_ONLY / HYBRID).
- Include modules: `Logger, CSymbolInfoCache, MoneyMath, CostCalculator,
  TickCollector, MarketMetrics, MomentumDetector, SignalEngine, PositionSizer,
  TradeExecutor, BreakEvenManager, TrailingManager, RiskManager, TradeJournal,
  StrategyController`.
- Cost-aware break-even (BUY/SELL asymmetric, round-trip commission + buffer).
- Trailing that only tightens; BE required first; stops-level/freeze respected.
- Risk: cooldown, max trades/day, consecutive-loss lock, daily-loss lock, abnormal-market veto.
- CSV journal with entry metrics, MFE/MAE, est. vs actual commission, exit reason.
- Linux validation: `tests/mirror.py`, `tests/test_logic.py` (23 tests),
  `scripts/static_check.py`.
- Docs: `README, docs/INPUTS_GUIDE, docs/BACKTEST_GUIDE, docs/RESEARCH_REPORT,
  ROADMAP, HANDOFF`.

### Fixed (during build)
- `TradeExecutor` signature: removed pre-declared dummy enum param.
- `test_logic` T12 expectation (correct value 1.0, not 0.1).
- `static_check`: regex stripper → state-machine stripper (false paren imbalance).

### Known limitations
- No MetaEditor compile or Strategy Tester run in this environment; both required
  on a Windows MT5 terminal before any profitability claim (see HANDOFF).
- Mid-price classification can be polluted by spread flicker (documented).
- Exit-reason SL/BE/TRAIL split is heuristic (documented).
