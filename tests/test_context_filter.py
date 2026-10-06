"""Context (candle) filter tests (EA v1.30, off by default).

Mirrors CMarketContextFilter: closed-bar EMA trend alignment + ATR cap,
fail-safe block on insufficient data, full passthrough when disabled.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mirror import context_gate

passed = failed = 0
def check(name, cond, extra=""):
    global passed, failed
    if cond: passed += 1; print(f"PASS {name} {extra}")
    else: failed += 1; print(f"FAIL {name} {extra}")

UP = [100.0 + i * 0.5 for i in range(60)] + [129.9]      # uptrend + forming bar
DOWN = [130.0 - i * 0.5 for i in range(60)] + [100.1]    # downtrend + forming bar
LOW_ATR = [5.0] * 60
HIGH_ATR = [500.0] * 60

# C1: uptrend -> BUY allowed, SELL blocked
ok, why = context_gate(UP, 50, True, None, None, True)
check("C1 uptrend allows BUY", ok and why == "OK", why)
ok, why = context_gate(UP, 50, True, None, None, False)
check("C1 uptrend blocks SELL", not ok and why == "CONTEXT_FILTER", why)

# C2: downtrend mirror
ok, why = context_gate(DOWN, 50, True, None, None, False)
check("C2 downtrend allows SELL", ok and why == "OK", why)
ok, why = context_gate(DOWN, 50, True, None, None, True)
check("C2 downtrend blocks BUY", not ok and why == "CONTEXT_FILTER", why)

# C3: insufficient bars -> fail-safe block (both directions)
SHORT = [100.0 + i for i in range(10)] + [109.0]
for want, nm in [(True, "BUY"), (False, "SELL")]:
    ok, why = context_gate(SHORT, 50, True, None, None, want)
    check(f"C3 short history blocks {nm}", not ok and why == "CTX_NO_DATA", why)

# C4: ATR above cap blocks even trend-aligned entries
ok, why = context_gate(UP, 50, True, HIGH_ATR, 100.0, True)
check("C4 high ATR blocks BUY", not ok and why == "VOLATILITY", why)

# C5: ATR below cap allows aligned entries
ok, why = context_gate(UP, 50, True, LOW_ATR, 100.0, True)
check("C5 low ATR allows BUY", ok and why == "OK", why)

# C6: disabled filter passes everything through (default config)
for closes, want in [(UP, True), (UP, False), (SHORT, True), (SHORT, False)]:
    ok, why = context_gate(closes, 50, False, None, None, want)
    check(f"C6 disabled passthrough want_buy={want}", ok and why == "OK", why)

# C7: vol-only mode (no trend): high ATR blocks, low ATR passes both sides
ok, why = context_gate(UP, 50, False, HIGH_ATR, 100.0, True)
check("C7 vol-only blocks on high ATR", not ok and why == "VOLATILITY", why)
ok, why = context_gate(UP, 50, False, LOW_ATR, 100.0, False)
check("C7 vol-only passes on low ATR", ok and why == "OK", why)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
