# Roadmap

- [x] Phase 1 — Research & architecture (spec review, module design, scaffolding)
- [x] Phase 2 — Core tick engine (collector, mid classification, rolling metrics)
- [x] Phase 3 — Signal engine (burst detector, spread/cooldown/position gates)
- [x] Phase 4 — Trade execution (CTrade market orders, money SL/TP, fill re-anchor)
- [x] Phase 5 — Cost-aware break-even (asymmetric, RT commission + buffer)
- [x] Phase 6 — Trailing stop (tighten-only, BE-first, broker constraints)
- [x] Phase 7 — Risk management (cooldown, day/consec/daily locks, abnormal veto)
- [x] Phase 8 — Logging & research (levels, CSV journal, MFE/MAE, exit reasons)
- [x] Phase 9 — Tester validation (Linux: 23 logic tests + static checks green;
      MT5 compile + real-tick runs pending on user terminal)
- [x] Phase 10 — Optimization readiness (TP modes, small param set, OOS protocol)
- [x] Next-phase (Linux) — lifecycle simulation harness `tests/test_simulation.py`, 8/8 green
- [x] Docs bilingual — `README_FA.md` (Persian), language links in `README.md`
- [ ] Next — Compile in MetaEditor (0 errors), run BACKTEST_GUIDE battery Tests A–H
- [ ] Next — Multi-symbol real-tick comparison (US30/US100/XAUUSD/EURUSD)
- [ ] Next — OOS validation; publish results in RESEARCH_REPORT (profitable or not)
- [x] Future — Risk-% position sizing extension point (`CPositionSizer`) — DONE v1.20
- [x] Future — Optional candle/volatility context filter (spec §1, off by default) — DONE v1.30
