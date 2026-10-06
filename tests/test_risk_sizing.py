"""Risk-based position sizing tests (next-phase feature, EA v1.10).

Semantics: V_risk = V_fixed * (equity*pct/100) / SLMoneyRef, and ALL money
inputs scale by k = V_risk/V_fixed so price geometry is identical to fixed mode.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mirror import money_to_distance, risk_volume

TS, TV = 0.01, 1.0
passed = failed = 0
def check(name, cond, extra=""):
    global passed, failed
    if cond: passed += 1; print(f"PASS {name} {extra}")
    else: failed += 1; print(f"FAIL {name} {extra}")

# R1: $10k equity, 0.5% risk, SL ref $1, fixed 0.01 -> risk $50 -> k=50 -> V=0.5
r = risk_volume(10000.0, 0.5, 0.01, 1.0, 0.01, 100.0, 1.0)
check("R1 volume + k", abs(r['volume'] - 0.5) < 1e-9 and abs(r['k'] - 50.0) < 1e-9
      and r['note'] == "OK", str(r))

# R2: price geometry invariant under k scaling
d_fixed = money_to_distance(1.0, TS, TV, 0.01)
d_risk = money_to_distance(1.0 * r['k'], TS, TV, r['volume'])
check("R2 SL price distance identical", abs(d_fixed - d_risk) < 1e-12,
      f"fixed={d_fixed} risk={d_risk}")
d_tp_f = money_to_distance(2.0, TS, TV, 0.01)
d_tp_r = money_to_distance(2.0 * r['k'], TS, TV, r['volume'])
check("R2 TP price distance identical", abs(d_tp_f - d_tp_r) < 1e-12)

# R3: cap at RiskMaxLot recomputes k and effective risk money
r = risk_volume(100000.0, 0.5, 0.01, 1.0, 0.01, 100.0, 1.0)  # want $500 -> V=5, cap 1.0
check("R3 capped", r['capped'] and abs(r['volume'] - 1.0) < 1e-9
      and abs(r['k'] - 100.0) < 1e-9 and abs(r['risk_money'] - 100.0) < 1e-9, str(r))

# R4: tiny equity -> below broker minimum -> no trade
r = risk_volume(100.0, 0.5, 0.01, 1.0, 0.01, 100.0, 1.0)  # want $0.50 -> k=0.5 -> V=0.005
check("R4 below-min blocks", r['volume'] == 0 and r['note'] == "BELOW_MIN", str(r))

# R5: invalid inputs fall back (no trade, explicit note)
for args, note in [((0.0, 0.5, 0.01, 1.0), "NO_EQUITY"),
                   ((10000.0, 0.5, 0.01, 0.0), "NO_SLREF"),
                   ((10000.0, 0.5, 0.0, 1.0), "NO_FIXEDLOT")]:
    r = risk_volume(*args, 0.01, 100.0, 1.0)
    check(f"R5 fallback {note}", r['volume'] == 0 and r['note'] == note, str(r))

# R6: fixed mode unaffected (k=1 identity)
check("R6 k=1 identity", abs(money_to_distance(1.0 * 1.0, TS, TV, 0.01) - d_fixed) < 1e-15)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
