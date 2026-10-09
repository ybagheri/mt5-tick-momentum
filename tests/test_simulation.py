"""End-to-end lifecycle simulation of the EA pipeline on synthetic tick streams.

Mirrors the MQL5 control flow tick-for-tick:
  collector (mid ring buffer) -> metrics -> burst -> signal gates ->
  market open w/ money SL/TP -> BE (cost-aware) -> trailing (tighten-only) -> close.

Covers spec section 46 scenarios at integrated level:
  S1 bullish burst -> BUY -> TP win | S2 bearish burst -> SELL -> TP win
  S3 spread spike blocks | S4 burst then instant crash -> STOP_LOSS
  S5 fresh bursts while open never add a position | S6 cooldown blocks re-entry
  S7 loss streak locks | S8 flat market, no signal
Exit reasons distinguish STOP_LOSS / TAKE_PROFIT / BREAK_EVEN / TRAILING_STOP.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mirror import (money_to_distance, estimate_commission, be_price_buy,
                    be_price_sell, dir_ratio, is_burst, signal_gate,
                    Metrics, RiskMirror, classify_exit, metrics_ready)

# --- synthetic symbol: point=0.01, tick 0.01 worth $1.00 per 1.0 lot ---
POINT = 0.01
TS, TV = 0.01, 1.0
VOL = 0.01
SL_M, TP_M = 1.0, 2.0
COMM, BUF, TRAIL_M = 6.0, 0.02, 0.50
WIN = 50

def sim_ticks(start, dirn, n, step, t0=1_000_000, dt_ms=200, spread=0.02):
    """Generate n ticks trending dirn (+1/-1/0) by step per tick in mid price."""
    out, mid, t = [], start, t0
    for _ in range(n):
        mid += dirn * step
        out.append((t, round(mid - spread / 2, 2), round(mid + spread / 2, 2)))
        t += dt_ms
    return out, t

class SimEA:
    def __init__(self):
        self.buf = []  # (t_ms, mid, dirn)
        self.prev_mid = None
        self.pos = None
        self.risk = RiskMirror(cooldown=5)
        self.now_s = 0
        self.trades = []          # closed trade dicts
        self.rejects = []
        self.while_open_bursts = 0
        self.sl_d = money_to_distance(SL_M, TS, TV, VOL)
        self.tp_d = money_to_distance(TP_M, TS, TV, VOL)
        self.trail_d = money_to_distance(TRAIL_M, TS, TV, VOL)
        self.rt_comm = estimate_commission(VOL, COMM, 2)
        self.be_gap = (self.rt_comm + BUF) * TS / (TV * VOL)

    def metrics(self):
        w = self.buf[-WIN:]
        if len(w) < 2: return None
        up = sum(1 for _, _, d in w[1:] if d == 1)
        down = sum(1 for _, _, d in w[1:] if d == -1)
        disp = w[-1][1] - w[0][1]
        dt = (w[-1][0] - w[0][0]) / 1000.0
        tps = (len(w) - 1) / dt if dt > 0 else 0.0
        return Metrics(up, down, round(abs(disp) / POINT), tps,
                       1 if disp > 0 else (-1 if disp < 0 else 0))

    def burst_now(self):
        m = self.metrics()
        if m is None: return False, None
        ok, _ = is_burst(m, 0.70, 10, 1.0)
        return (ok and m.disp_sign != 0), (m.disp_sign if ok else 0)

    def on_tick(self, t_ms, bid, ask):
        self.now_s = t_ms // 1000
        mid = (bid + ask) / 2
        d = 0
        if self.prev_mid is not None:
            d = 1 if mid > self.prev_mid else (-1 if mid < self.prev_mid else 0)
        self.prev_mid = mid
        self.buf.append((t_ms, mid, d))
        spread_pts = round((ask - bid) / POINT)

        if self.pos is not None:
            burst, _ = self.burst_now()
            if burst: self.while_open_bursts += 1
            self._manage(bid, ask)
            return

        m = self.metrics()
        if m is None:
            self.rejects.append("WARMUP"); return
        # metrics readiness now requires a FULL window (parity with CMarketMetrics)
        if not metrics_ready(len(self.buf[-WIN:]), WIN):
            self.rejects.append("WARMUP"); return
        ok, why = is_burst(m, 0.70, 10, 1.0)
        bdir = m.disp_sign if ok else 0
        sig, reason = signal_gate(ok, bdir, spread_pts, 100, 0, 1,
                                  self.risk.in_cooldown(self.now_s),
                                  self.risk.locked, False)
        if sig is None:
            self.rejects.append(reason); return
        is_buy = (sig == "BUY")
        entry = ask if is_buy else bid
        sl = entry - self.sl_d if is_buy else entry + self.sl_d
        tp = entry + self.tp_d if is_buy else entry - self.tp_d
        self.risk.notify_open()          # counted here, never again on close
        be = (be_price_buy(entry, VOL, TS, TV, COMM, BUF) if is_buy
              else be_price_sell(entry, VOL, TS, TV, COMM, BUF))
        self.pos = dict(is_buy=is_buy, entry=entry, sl=sl, tp=tp, be=be,
                        be_done=False, trail_active=False, mfe=entry,
                        open_t=self.now_s)

    def _manage(self, bid, ask):
        p = self.pos
        px = bid if p['is_buy'] else ask  # exit-side price
        p['mfe'] = max(p['mfe'], px) if p['is_buy'] else min(p['mfe'], px)
        # 1) stop / tp hit (checked before moving stops, like broker fills)
        if p['is_buy']:
            if px <= p['sl'] + 1e-12:
                self._close(px, "BREAK_EVEN" if abs(p['sl'] - p['be']) < 1e-9
                            else ("TRAILING_STOP" if p['sl'] > p['entry'] else "STOP_LOSS"))
                return
            if px >= p['tp'] - 1e-12:
                self._close(px, "TAKE_PROFIT"); return
            # 2) BE then trailing
            if px >= p['entry'] + self.be_gap - 1e-12:
                if p['sl'] < p['be']: p['sl'] = p['be']
                p['be_done'] = True
            if p.get('be_done'):
                ns = px - self.trail_d
                if ns > p['sl'] and ns >= p['be']:
                    p['sl'] = ns; p['trail_active'] = True
        else:
            if px >= p['sl'] - 1e-12:
                self._close(px, "BREAK_EVEN" if abs(p['sl'] - p['be']) < 1e-9
                            else ("TRAILING_STOP" if p['sl'] < p['entry'] else "STOP_LOSS"))
                return
            if px <= p['tp'] + 1e-12:
                self._close(px, "TAKE_PROFIT"); return
            if px <= p['entry'] - self.be_gap + 1e-12:
                if p['sl'] == 0 or p['sl'] > p['be']: p['sl'] = p['be']
                p['be_done'] = True
            if p.get('be_done'):
                ns = px + self.trail_d
                if (p['sl'] == 0 or ns < p['sl']) and ns <= p['be']:
                    p['sl'] = ns; p['trail_active'] = True

    def _close(self, px, reason):
        p = self.pos
        gross = ((px - p['entry']) if p['is_buy'] else (p['entry'] - px)) / TS * TV * VOL
        net = gross - self.rt_comm  # actual == estimate in sim
        # reason derived from the record, exactly like CTradeJournal::ClassifyExit
        reason = classify_exit(px, p['tp'], p['sl'], p['be_done'],
                               p['trail_active'], net, TS, p['is_buy'])
        self.trades.append(dict(dir="BUY" if p['is_buy'] else "SELL",
                                entry=p['entry'], exit=px, gross=round(gross, 4),
                                net=round(net, 4), reason=reason,
                                hold=self.now_s - p['open_t']))
        # trade counted once (on open); close only updates P/L, streak, cooldown
        self.risk.notify_close(self.now_s, net)
        self.pos = None

    def feed(self, ticks):
        for t, b, a in ticks:
            self.on_tick(t, b, a)

    def feed_until_closed(self, ticks, limit=1):
        """Feed tick-by-tick; stop once `limit` trades have closed. Returns rest."""
        n0 = len(self.trades)
        for i, (t, b, a) in enumerate(ticks):
            self.on_tick(t, b, a)
            if len(self.trades) - n0 >= limit:
                return ticks[i + 1:]
        return []

passed = failed = 0
def check(name, cond, extra=""):
    global passed, failed
    if cond: passed += 1; print(f"PASS {name} {extra}")
    else: failed += 1; print(f"FAIL {name} {extra}")

# S1: bullish burst -> BUY -> runs to TP
ea = SimEA()
warm, t = sim_ticks(100.0, 0, WIN, 0.0)
burst, t = sim_ticks(100.0, 1, WIN, 0.05, t0=t)   # +2.5 over window, ratio 1.0
run, t = sim_ticks(burst[-1][1] + 0.01, 1, 200, 0.10, t0=t)
ea.feed(warm + burst + run)
check("S1 BUY opened, TP win, net>0",
      len(ea.trades) >= 1 and ea.trades[0]['dir'] == "BUY"
      and ea.trades[0]['reason'] == "TAKE_PROFIT" and ea.trades[0]['net'] > 0,
      str(ea.trades[0] if ea.trades else "no trades"))

# S2: bearish mirror -> SELL -> TP
ea = SimEA()
warm, t = sim_ticks(100.0, 0, WIN, 0.0)
burst, t = sim_ticks(100.0, -1, WIN, 0.05, t0=t)
run, t = sim_ticks(burst[-1][1] - 0.01, -1, 200, 0.10, t0=t)
ea.feed(warm + burst + run)
check("S2 SELL opened, TP win, net>0",
      len(ea.trades) >= 1 and ea.trades[0]['dir'] == "SELL"
      and ea.trades[0]['reason'] == "TAKE_PROFIT" and ea.trades[0]['net'] > 0,
      str(ea.trades[0] if ea.trades else "no trades"))

# S3: spread spike blocks entry despite burst
ea = SimEA()
warm, t = sim_ticks(100.0, 0, WIN, 0.0)
wide, t = sim_ticks(100.0, 1, WIN, 0.05, t0=t, spread=5.0)  # 500 pts spread
ea.feed(warm + wide)
check("S3 no entry on wide spread", len(ea.trades) == 0 and ea.pos is None
      and "SPREAD" in ea.rejects)

# S4: small burst (entry, no BE yet) then instant crash -> STOP_LOSS, net<0
ea = SimEA()
warm, t = sim_ticks(100.0, 0, WIN, 0.0)
b, t = sim_ticks(100.0, 1, 8, 0.03, t0=t)          # +0.24: entry, BE not reached
crash, t = sim_ticks(b[-1][1] + 0.01, -1, 5, 0.60, t0=t)  # -3.0 crash
ea.feed(warm + b + crash)
check("S4 crash stops out at SL, net<0",
      len(ea.trades) == 1 and ea.trades[0]['reason'] == "STOP_LOSS"
      and ea.trades[0]['net'] < 0, str(ea.trades[0] if ea.trades else "none"))

# S5: fresh bursts while a position is held never add a position
ea = SimEA()
warm, t = sim_ticks(100.0, 0, WIN, 0.0)
b1, t = sim_ticks(100.0, 1, 8, 0.03, t0=t)          # entry, stays open (+0.24)
b2, t = sim_ticks(b1[-1][1] + 0.01, 1, 30, 0.03, t0=t)  # fresh bursts, +0.9 (< TP)
ea.feed(warm + b1 + b2)
check("S5 one open position, no extra trades",
      len(ea.trades) == 0 and ea.pos is not None and ea.while_open_bursts >= 1,
      f"trades={len(ea.trades)} open={ea.pos is not None} "
      f"bursts_while_open={ea.while_open_bursts}")

# S6: cooldown blocks immediate re-entry after a close
e = SimEA()
w, t = sim_ticks(100.0, 0, WIN, 0.0)
b, t = sim_ticks(100.0, 1, 8, 0.03, t0=t)
e.feed(w + b)
assert e.pos is not None, "S6 setup: no entry opened"
cont, t = sim_ticks(b[-1][1] + 0.01, 1, 100, 0.10, t0=t)
e.feed_until_closed(cont)                            # TP close
n_after_close = len(e.trades)
last_t = e.buf[-1][0]
c, _ = sim_ticks((e.buf[-1][1]), 1, 10, 0.05, t0=last_t + 200)  # ~2s after close
e.feed(c)
check("S6 cooldown blocks re-entry", len(e.trades) == n_after_close and e.pos is None,
      f"trades={len(e.trades)} rejects_tail={e.rejects[-3:]}")

# S7: five consecutive SLs -> CONSEC_LOSS lock, 6th setup rejected
# (fresh stream per iteration with SHARED risk state = five separate loss episodes)
shared_risk = None
total_s7 = 0
s7_sixth_trades = None
t = 1_000_000
for i in range(6):
    e = SimEA()
    if shared_risk is not None: e.risk = shared_risk
    w, t = sim_ticks(100.0, 0, WIN, 0.0, t0=t)
    b, t = sim_ticks(100.0, 1, 8, 0.03, t0=t)
    r, t = sim_ticks(b[-1][1] + 0.01, -1, 2, 0.60, t0=t)  # -1.2: SL on 2nd tick
    f, t = sim_ticks(r[-1][1], 0, 10, 0.0, t0=t)
    e.feed(w + b + r + f)
    total_s7 += len(e.trades)
    shared_risk = e.risk
    if i == 5: s7_sixth_trades = len(e.trades)
check("S7 loss streak locks at 5", shared_risk.locked
      and shared_risk.reason == "CONSEC_LOSS"
      and total_s7 == 5 and s7_sixth_trades == 0,
      f"locked={shared_risk.locked} reason={shared_risk.reason} "
      f"total={total_s7} sixth={s7_sixth_trades}")

# S8: flat market -> never trades
e = SimEA()
f, _ = sim_ticks(100.0, 0, 400, 0.0)
e.feed(f)
check("S8 flat => no trades", len(e.trades) == 0 and e.pos is None)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
