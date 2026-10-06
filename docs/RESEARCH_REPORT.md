# Research Report — Tick Momentum Burst hypothesis

**Status: implementation complete, market validation pending.**
No live or Strategy-Tester market runs were possible in this Linux build environment
(no MT5 terminal). All claims below concern *logic correctness*, not profitability.

## Question

> Can short-term directional behaviour in the MT5 tick stream provide a repeatable edge
> after spread, commission, slippage and realistic execution?

## What was built to answer it

Deterministic, fully-instrumented EA (v1.00): every entry carries its tick metrics
(ratio, displacement, tick-rate) into the CSV journal together with spread, estimated
vs actual commission, MFE/MAE, holding time and exit reason — so expectancy can be
attributed to signal quality vs cost drag.

## Logic-level evidence (Linux mirror + static checks, 2026-10-06)

- `tests/test_logic.py`: **23/23 pass** — money↔distance round-trip, BE symmetry
  (BUY/SELL mirror to <1e-9), cost-covered trigger ≡ BE gap, spread block, trailing
  monotonicity both sides, cooldown/daily-lock, spec-dependent distances, burst gates.
- `scripts/static_check.py`: **pass** — balanced syntax, required handlers, magic+symbol
  filtering, no martingale/grid patterns, BE asymmetry, trailing-only-tightens markers.

## Lifecycle simulation (Linux, 2026-10-07 — "next phase" functional verification)

`tests/test_simulation.py` replays synthetic tick streams through a tick-for-tick
mirror of the full pipeline (collector → metrics → burst → gates → money SL/TP →
BE → trailing → close). **8/8 pass:**

| # | Scenario | Result |
|---|---|---|
| S1 | Bullish burst → BUY → continuation | `TAKE_PROFIT`, net +1.91 |
| S2 | Bearish burst → SELL → continuation (mirror) | `TAKE_PROFIT`, net +1.91 |
| S3 | Burst + 500-pt spread | No entry (`SPREAD` reject) |
| S4 | Entry then instant crash | `STOP_LOSS`, net −1.22 |
| S5 | Fresh bursts while a position is held (34 bursts) | No second position |
| S6 | Fresh burst ~2 s after close | Blocked (`COOLDOWN`) |
| S7 | Five consecutive SL episodes | `CONSEC_LOSS` lock, 6th setup rejected |
| S8 | Flat market, 400 ticks | No trades |

Two findings worth carrying into real-tick testing: (a) burst entries trigger after
only a few ticks once displacement crosses the threshold, so most of the "burst
window" is post-entry drift — continuation quality, not detection speed, decides the
trade; (b) post-crash counter-bursts are legitimate SELL signals in the sim, which is
correct behaviour but means loss streaks in real markets may interleave with
counter-trend wins rather than clean SL sequences.

## v1.30 addendum — context filter

The optional candle module (`CMarketContextFilter`, default OFF) exists so the
baseline tick hypothesis can be compared against trend-filtered and vol-capped
variants in the Strategy Tester without touching core signal code. Falsification
rule to apply per variant: if a filter halves the trade count without improving
net expectancy or profit factor out-of-sample, it is complexity without edge —
remove it rather than stacking more vetoes.

## Specification issues found and resolved

1. **Commission ambiguity.** Spec's example ($6×0.01=$0.06) reads as a single charge,
   but MT5 charges commission *per deal* (open AND close). The EA estimates round-trip
   as 2× one side by default (`InpCommissionDoubledRT=true`) and journals actual both-leg
   commission. Conservative; documented.
2. **SL=$1 gross vs net.** A $1 price-move stop costs ≈$1 + spread + commission net.
   Documented as gross; journal reports net so expectancy is honest.
3. **TP-mode gap.** `TRAILING_ONLY` with trailing disabled is now an init error.
4. **Exit-reason granularity.** MT5 reports generic stop-outs; SL vs BE vs TRAIL is
   disambiguated via controller state (BE-done flag) + journal SL snapshot — heuristic,
   documented as such.
5. **Mid-price classification.** `Mid=(Bid+Ask)/2` per spec; spread changes alone can
   flip classification. Documented limitation; spread filter mitigates.

## Prior reasons for scepticism (to test, not assume)

- Micro-momentum must overcome round-trip costs on every trade; with 1:2 gross R:R the
  required win rate rises materially once spread+commission are included.
- Broker CFD ticks ≠ order flow; apparent "imbalance" may be quote noise or spread artefact.
- Bursts cluster in volatile regimes where slippage and spread widen exactly when signals fire.

## Verdict

**Unproven — by design.** The EA is a measurement instrument. Run the battery in
`docs/BACKTEST_GUIDE.md`, demand OOS consistency across symbols, and accept NO as a
successful outcome. Do not curve-fit the small parameter set to manufacture profit.
