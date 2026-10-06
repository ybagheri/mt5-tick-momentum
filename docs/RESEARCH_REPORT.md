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
