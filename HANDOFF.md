# HANDOFF — Tick Momentum Burst EA v1.20 (2026-10-07)

## Architecture
Single EA `MQL5/Experts/TickMomentumBurstEA.mq5` + 15 `.mqh` modules under
`MQL5/Include/TickMomentum/` (collector → metrics → detector → signal → executor →
BE → trailing → risk → journal, orchestrated by `CStrategyController` state machine).
Full map in `README.md`.

## Completed work (Phases 1–10)
All phases implemented in one build pass (empty repo, greenfield). Entry rules: burst
(ratio ≥ 0.70 ∧ displacement ≥ 10 pts ∧ agreement ∧ tick-rate ≥ 1/s) + spread ≤ max +
no position + no cooldown + no risk lock → market BUY/SELL with money-derived SL/TP.
SL $1 / TP $2 defaults; BE = entry ± (round-trip est. commission + $0.02 buffer);
trailing $0.50 tighten-only after BE; TP modes FIXED/TRAILING_ONLY/HYBRID.
v1.20 adds optional risk-% sizing (off by default): volume scales so SL money =
equity × pct, all money targets scaled by k, price geometry unchanged.

## Test status
- `tests/test_logic.py` — 23/23 PASS (covers spec §46 Tests 1–10, 12 at logic level).
- `tests/test_simulation.py` — 8/8 PASS (integrated lifecycle: BUY/SELL TP, spread veto,
  crash SL, no-averaging under 34 bursts, cooldown, consec-loss lock, flat-market silence).
- `tests/test_risk_sizing.py` — 9/9 PASS (risk volume/k, geometry invariance, caps, blocks).
- `scripts/static_check.py` — PASS.
- **NOT done (environment): no MetaEditor compile, no Strategy Tester runs.**
  First action on a Windows MT5 terminal: F7 compile → Test A visual real-tick run.

## Known limitations
1. MT5 compile/tester validation pending (see above).
2. Mid-price classification sensitive to spread flicker; mitigated by spread filter.
3. Exit SL-vs-BE-vs-TRAIL split is heuristic (controller BE flag + journal snapshot).
4. Commission default ($6 one-side, doubled RT) is an assumption — match to broker.
5. Defaults are unoptimized research values; no profitability claimed.

## Next phase (whoever continues)
1. Compile, fix any build-specific warnings (e.g. `SYMBOL_FILLING_MODE` availability).
2. Execute `docs/BACKTEST_GUIDE.md` battery A–H; record in `docs/RESEARCH_REPORT.md`.
3. OOS validation before any parameter change; keep param set small.
