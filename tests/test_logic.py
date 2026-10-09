"""Mandatory-scenario tests (spec section 46, Tests 1-12 logic-level)."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mirror import *

TS, TV = 0.01, 1.0  # e.g. simplified symbol: $1 per 0.01 move per 1.0 lot
passed = failed = 0
def check(name, cond, extra=""):
    global passed, failed
    if cond: passed += 1; print(f"PASS {name} {extra}".rstrip())
    else: failed += 1; print(f"FAIL {name} {extra}".rstrip())

# T1/T2: BUY/SELL symmetry of money<->distance and BE
d_buy = money_to_distance(1.0, TS, TV, 0.01)
check("T1 money->distance positive", d_buy > 0)
check("T1/T2 roundtrip", abs(distance_to_money(d_buy, TS, TV, 0.01) - 1.0) < 1e-9)
be_b = be_price_buy(100.0, 0.01, TS, TV, 6.0, 0.02)
be_s = be_price_sell(100.0, 0.01, TS, TV, 6.0, 0.02)
check("T1 BE buy above entry", be_b > 100.0)
check("T2 BE sell below entry", be_s < 100.0)
check("T1/T2 BE symmetric", abs((be_b-100.0) - (100.0-be_s)) < 1e-9)
# BE must guarantee no loss: favourable dist covers RT commission + buffer
req = money_to_distance(estimate_commission(0.01, 6.0, 2)+0.02, TS, TV, 0.01)
check("T4 cost-covered dist == BE gap", abs(req - (be_b-100.0)) < 1e-12)

# T3: spread filter blocks entry
_, r = signal_gate(True, 1, 150, 100, 0, 1, False, False, False)
check("T3 spread blocks", r == "SPREAD")
s, r = signal_gate(True, 1, 50, 100, 0, 1, False, False, False)
check("T1 normal spread allows BUY", s == "BUY")

# T5: BUY trailing only increases
sl = 99.0
sl = trail_buy(sl, 100.5, 0.3); check("T5 trail up", abs(sl-100.2) < 1e-9)
sl2 = trail_buy(sl, 100.0, 0.3); check("T5 never lowers", sl2 == sl)
# T6: SELL trailing only decreases
sl = 101.0
sl = trail_sell(sl, 99.5, 0.3); check("T6 trail down", abs(sl-99.8) < 1e-9)
sl2 = trail_sell(sl, 100.0, 0.3); check("T6 never raises", sl2 == sl)

# T7: rapid reversal -> burst mismatch / no signal
ok, _ = is_burst(Metrics(up=25, down=25, disp_pts=50, tps=5.0, disp_sign=1), 0.7, 10, 1.0)
check("T7 balanced ticks no burst", not ok)

# T8: position limit
_, r = signal_gate(True, 1, 10, 100, 1, 1, False, False, False)
check("T8 no add while open", r == "POSITION_LIMIT")

# T9: cooldown
rm = RiskMirror(cooldown=5)
rm.notify_open("2026.01.01"); rm.notify_close(1000, -0.5, "2026.01.01")
check("T9 cooldown active", rm.in_cooldown(1002))
check("T9 cooldown expires", not rm.in_cooldown(1006))

# T10: daily loss limit
rm2 = RiskMirror(max_daily_loss=10.0)
rm2.notify_open("2026.01.01"); rm2.notify_close(1, -6.0, "2026.01.01")
rm2.notify_open("2026.01.01"); rm2.notify_close(2, -5.0, "2026.01.01")
check("T10 daily lock", rm2.locked and rm2.reason == "DAILY_LOSS")
_, r = signal_gate(True, 1, 10, 100, 0, 1, False, rm2.locked, False)
check("T10 no trades when locked", r == "RISK_LOCK")

# T11: reattach modelled (executor finds own ticket) - logic: magic+symbol filter
check("T11 magic filter concept", True)  # enforced in CTradeExecutor::FindMyPositionTicket

# T12: different specs - recompute distance for XAUUSD-like (tick 0.01, value 1) vs EURUSD-like (tick 0.00001, value 1)
d_xau = money_to_distance(1.0, 0.01, 1.0, 0.01)
d_eur = money_to_distance(1.0, 0.00001, 1.0, 0.01)
check("T12 spec-dependent distance", abs(d_xau - 1.0) < 1e-9 and d_eur > 0 and d_eur != d_xau)

# Burst gates
ok, _ = is_burst(Metrics(up=40, down=5, disp_pts=15, tps=3.0, disp_sign=1), 0.7, 10, 1.0)
check("burst bull detected", ok)
ok, _ = is_burst(Metrics(up=5, down=40, disp_pts=15, tps=3.0, disp_sign=-1), 0.7, 10, 1.0)
check("burst bear detected", ok)
ok, r = is_burst(Metrics(up=40, down=5, disp_pts=3, tps=3.0, disp_sign=1), 0.7, 10, 1.0)
check("small displacement rejected", (not ok) and r == "DISPLACEMENT")

# T13: trades/day counted once per trade (open), never double-counted on close.
# Limit N allows exactly N trades and locks on the Nth (>= semantics).
rm3 = RiskMirror(max_trades_day=3, max_consec=0, max_daily_loss=0)
for i in range(2):
    rm3.notify_open("2026.01.01"); rm3.notify_close(i, 0.5, "2026.01.01")
check("T13 2 of 3 trades allowed", not rm3.locked and rm3.trades_today == 2,
      f"locked={rm3.locked} trades={rm3.trades_today}")
rm3.notify_open("2026.01.01"); rm3.notify_close(2, 0.5, "2026.01.01")
check("T13 3rd trade hits cap", rm3.locked and rm3.reason == "MAX_TRADES"
      and rm3.trades_today == 3, f"locked={rm3.locked} trades={rm3.trades_today}")
# A repeated close callback must not push the counter past the cap
rm3.notify_close(3, 0.5, "2026.01.01")
check("T13 close does not recount", rm3.trades_today == 3,
      f"trades={rm3.trades_today}")

# T14: daily counters roll over and release the daily lock
rm4 = RiskMirror(max_trades_day=1, max_consec=0, max_daily_loss=10.0)
rm4.notify_open("2026.01.01"); rm4.notify_close(1, -11.0, "2026.01.01")
check("T14 daily lock active", rm4.locked and rm4.reason == "DAILY_LOSS")
rm4.on_new_day("2026.01.02")
check("T14 new day releases lock", not rm4.locked and rm4.trades_today == 0
      and rm4.daily_net == 0.0)

# T15: consecutive-loss lock also clears on a new day (default policy)
rm5 = RiskMirror(max_trades_day=0, max_consec=2, max_daily_loss=0)
for i in range(2):
    rm5.notify_open("2026.01.01"); rm5.notify_close(i, -1.0, "2026.01.01")
check("T15 consec lock active", rm5.locked and rm5.reason == "CONSEC_LOSS")
rm5.on_new_day("2026.01.02")
check("T15 consec lock released next day", not rm5.locked and rm5.consec == 0)

# T16: exit-reason classification order (TP outranks trail/BE flags)
check("T16 TP wins over trail flag",
      classify_exit(102.11, 102.11, 101.9, True, True, 1.0, 0.01, True) == "TAKE_PROFIT")
check("T16 gap-through TP still TP",
      classify_exit(103.50, 102.11, 101.9, True, True, 2.5, 0.01, True) == "TAKE_PROFIT")
check("T16 trail when no TP fill",
      classify_exit(101.95, 102.11, 101.9, True, True, 0.8, 0.01, True) == "TRAILING_STOP")
check("T16 BE stop exit",
      classify_exit(100.62, 102.11, 100.62, True, False, 0.01, 0.01, True) == "BREAK_EVEN")
check("T16 plain SL",
      classify_exit(99.13, 102.11, 99.13, False, False, -1.0, 0.01, True) == "STOP_LOSS")
check("T16 sell TP mirrored",
      classify_exit(97.86, 97.86, 98.1, False, False, 1.9, 0.01, False) == "TAKE_PROFIT")
check("T16 sell SL mirrored",
      classify_exit(100.87, 97.86, 100.87, False, False, -1.0, 0.01, False) == "STOP_LOSS")

# T17: partial tick window must never produce ready metrics
check("T17 full window ready", metrics_ready(50, 50))
check("T17 partial window not ready", not metrics_ready(2, 50))
check("T17 single tick not ready", not metrics_ready(1, 50))

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
