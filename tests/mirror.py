"""Python mirror of the EA's pure math/logic for Linux-side validation.
Mirrors: MoneyMath, CostCalculator, burst detection, signal gates,
trailing monotonicity, break-even, risk manager.
"""
from dataclasses import dataclass

def money_to_distance(money, tick_size, tick_value, volume):
    if volume <= 0 or money <= 0 or tick_size <= 0 or tick_value <= 0:
        return 0.0
    return money * tick_size / (tick_value * volume)

def distance_to_money(dist, tick_size, tick_value, volume):
    if volume <= 0 or dist <= 0 or tick_size <= 0 or tick_value <= 0:
        return 0.0
    return dist / tick_size * tick_value * volume

def estimate_commission(volume, per_lot, sides=2):
    return per_lot * volume * sides

def be_price_buy(entry_ask, volume, tick_size, tick_value, per_lot, buffer_money, doubled=True):
    costs = estimate_commission(volume, per_lot, 2 if doubled else 1) + max(0.0, buffer_money)
    return entry_ask + money_to_distance(costs, tick_size, tick_value, volume)

def be_price_sell(entry_bid, volume, tick_size, tick_value, per_lot, buffer_money, doubled=True):
    costs = estimate_commission(volume, per_lot, 2 if doubled else 1) + max(0.0, buffer_money)
    return entry_bid - money_to_distance(costs, tick_size, tick_value, volume)

@dataclass
class Metrics:
    up: int; down: int; disp_pts: int; tps: float; disp_sign: int  # +1/-1/0

def dir_ratio(up, down):
    denom = up + down
    if denom == 0: return 0.0, 0
    r = max(up, down) / denom
    d = 1 if up > down else (-1 if down > up else 0)
    return r, d

def is_burst(m: Metrics, min_ratio, min_move_pts, min_tps):
    if m.disp_sign == 0: return False, "NO_DOMINANCE"
    r, d = dir_ratio(m.up, m.down)
    if d == 0: return False, "NO_DOMINANCE"
    if r < min_ratio: return False, "RATIO"
    if m.disp_pts < min_move_pts: return False, "DISPLACEMENT"
    if m.tps < min_tps: return False, "TICKRATE"
    if d > 0 and m.disp_sign <= 0: return False, "DIR_MISMATCH"
    if d < 0 and m.disp_sign >= 0: return False, "DIR_MISMATCH"
    return True, "BURST"

def signal_gate(burst_ok, burst_dir, spread_pts, max_spread, my_pos, max_pos, cooldown, locked, abnormal):
    if locked: return None, "RISK_LOCK"
    if cooldown: return None, "COOLDOWN"
    if my_pos >= max_pos: return None, "POSITION_LIMIT"
    if spread_pts > max_spread: return None, "SPREAD"
    if abnormal: return None, "ABNORMAL_MARKET"
    if not burst_ok: return None, "NO_BURST"
    return ("BUY" if burst_dir > 0 else "SELL"), "OK"

class RiskMirror:
    def __init__(self, max_trades_day=50, max_consec=5, max_daily_loss=10.0, cooldown=5):
        self.max_trades_day=max_trades_day; self.max_consec=max_consec
        self.max_daily_loss=max_daily_loss; self.cooldown=cooldown
        self.last_close=None; self.trades_today=0; self.consec=0
        self.daily_net=0.0; self.locked=False; self.reason=""
    def in_cooldown(self, now):
        if self.last_close is None: return False
        return (now - self.last_close) < self.cooldown
    def notify_close(self, now, net):
        self.last_close=now; self.trades_today+=1; self.daily_net+=net
        self.consec = self.consec+1 if net<0 else 0
        self._eval()
    def _eval(self):
        if self.max_trades_day>0 and self.trades_today>=self.max_trades_day:
            self.locked=True; self.reason="MAX_TRADES"
        if self.max_consec>0 and self.consec>=self.max_consec:
            self.locked=True; self.reason="CONSEC_LOSS"
        if self.max_daily_loss>0 and self.daily_net<=-self.max_daily_loss:
            self.locked=True; self.reason="DAILY_LOSS"

def trail_buy(current_sl, bid, trail_dist):
    new_sl = bid - trail_dist
    if new_sl > current_sl: return new_sl
    return current_sl

def trail_sell(current_sl, ask, trail_dist):
    new_sl = ask + trail_dist
    if current_sl == 0 or new_sl < current_sl: return new_sl
    return current_sl

def risk_volume(equity, risk_pct, fixed_lot, sl_money_ref,
                vol_min, vol_max, max_lot):
    """Mirror of CPositionSizer::ComputeRiskVolume.
    Returns dict(volume, k, risk_money, capped, note). volume 0 = no trade."""
    if equity is None or equity <= 0: return dict(volume=0, k=0, risk_money=0, capped=False, note="NO_EQUITY")
    if sl_money_ref is None or sl_money_ref <= 0: return dict(volume=0, k=0, risk_money=0, capped=False, note="NO_SLREF")
    if fixed_lot is None or fixed_lot <= 0: return dict(volume=0, k=0, risk_money=0, capped=False, note="NO_FIXEDLOT")
    want = equity * risk_pct / 100.0
    k = want / sl_money_ref
    v = fixed_lot * k
    cap = min(vol_max, max_lot)
    capped = False
    if v > cap: v, capped = cap, True
    # normalize down to step (step assumed to divide evenly here; caller passes step)
    v = max(0.0, v)
    if v < vol_min - 1e-12:
        return dict(volume=0, k=0, risk_money=0, capped=capped, note="BELOW_MIN")
    k_eff = v / fixed_lot
    return dict(volume=v, k=k_eff, risk_money=sl_money_ref * k_eff,
                capped=capped, note="CAPPED" if capped else "OK")
