# Changelog

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
