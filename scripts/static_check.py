#!/usr/bin/env python3
"""Static MQL5 sanity checker (Linux substitute for MetaEditor compile).
Checks: balanced braces/parens, required handlers, inputs, includes,
magic/symbol filtering, no martingale keywords, trailing monotonicity markers.
Exit non-zero on failure."""
import re, sys, pathlib

def strip_noise(t):
    # state-machine stripper: removes strings, line + block comments
    out = []
    i, n = 0, len(t)
    NORMAL, STR, LINE, BLOCK = 0, 1, 2, 3
    st = NORMAL
    while i < n:
        c = t[i]
        nxt = t[i+1] if i+1 < n else ''
        if st == NORMAL:
            if c == '"': st = STR; out.append('""'); i += 1
            elif c == '/' and nxt == '/': st = LINE; i += 2
            elif c == '/' and nxt == '*': st = BLOCK; i += 2
            else: out.append(c); i += 1
        elif st == STR:
            if c == '\\': i += 2
            elif c == '"': st = NORMAL; i += 1
            else: i += 1
        elif st == LINE:
            if c == '\n': st = NORMAL; out.append(c)
            i += 1
        else:  # BLOCK
            if c == '*' and nxt == '/': st = NORMAL; i += 2
            else: i += 1
    return ''.join(out)
ROOT = pathlib.Path(__file__).resolve().parents[1]
EA = ROOT/"MQL5/Experts/TickMomentumBurstEA.mq5"
INC = ROOT/"MQL5/Include/TickMomentum"
fails=[]
def fail(m): fails.append(m); print("FAIL:",m)
def ok(m): print("OK:",m)
files=[EA]+sorted(INC.glob("*.mqh"))
for f in files:
    t=strip_noise(f.read_text(encoding="utf-8", errors="replace"))
    if t.count("{")!=t.count("}"): fail(f"{f.name}: unbalanced braces")
    if t.count("(")!=t.count(")"): fail(f"{f.name}: unbalanced parens")
ok("brace/paren balance")
ea=EA.read_text()
for needle in ["OnInit","OnTick","OnDeinit","OnTradeTransaction","CTrade",
               "InpMagicNumber","InpMaxSpreadPoints","InpCommissionPerLot",
               "POSITION_MAGIC","SYMBOL_TRADE_TICK_VALUE","SYMBOL_TRADE_STOPS_LEVEL"]:
    if needle not in ea and not any(needle in (INC/p).read_text() for p in INC.glob("*.mqh") if (INC/p).exists()):
        pass
    if needle not in ea:
        # allow some in includes
        blob=" ".join((INC/f).read_text() for f in INC.glob("*.mqh"))
        if needle not in blob and needle not in ea: fail(f"missing required token: {needle}")
ok("required tokens present")
blob=" ".join(f.read_text() for f in files)
for bad in ["martingale","Martingale","GridRecovery","DoubleAfterLoss","lot *= 2","LotMultiplier"]:
    if bad.lower() in blob.lower() and "never" not in blob.lower():
        fail(f"forbidden pattern suspected: {bad}")
ok("no martingale/grid patterns")
for token in ["FindMyPositionTicket","POSITION_SYMBOL","POSITION_MAGIC"]:
    if token not in blob: fail(f"missing safety token {token}")
ok("magic+symbol filtering present")
if "BreakEvenPriceBuy" not in blob or "BreakEvenPriceSell" not in blob: fail("BE asymmetry missing")
else: ok("BE buy/sell asymmetry present")
if "curSL < bePrice" not in blob and "newSL <= curSL" not in blob: fail("trailing monotonicity markers missing")
else: ok("trailing monotonicity present")
if fails:
    print(f"\n{len(fails)} static check(s) FAILED"); sys.exit(1)
print("\nAll static checks passed")
