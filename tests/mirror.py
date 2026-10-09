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
    """Mirror of CRiskManager.

    trades_today is counted on OPEN only (never again on close), so a trade is
    counted exactly once even if the close callback is seen twice.
    """
    def __init__(self, max_trades_day=50, max_consec=5, max_daily_loss=10.0,
                 cooldown=5, reset_consec_on_new_day=True):
        self.max_trades_day=max_trades_day; self.max_consec=max_consec
        self.max_daily_loss=max_daily_loss; self.cooldown=cooldown
        self.reset_consec_on_new_day=reset_consec_on_new_day
        self.last_close=None; self.day_key=None; self.trades_today=0; self.consec=0
        self.daily_net=0.0; self.locked=False; self.reason=""
    def on_new_day(self, key):
        if self.day_key is not None and key == self.day_key: return
        self.day_key=key; self.trades_today=0; self.daily_net=0.0
        if self.reset_consec_on_new_day: self.consec=0
        if self.reason in ("DAILY_LOSS", "MAX_TRADES"):
            self.locked=False; self.reason=""
        elif self.reason=="CONSEC_LOSS" and self.reset_consec_on_new_day:
            self.locked=False; self.reason=""
    def in_cooldown(self, now):
        if self.last_close is None: return False
        return (now - self.last_close) < self.cooldown
    def notify_open(self, day_key=None):
        if day_key is not None: self.on_new_day(day_key)
        self.trades_today+=1
        self._eval()
    def notify_close(self, now, net, day_key=None):
        if day_key is not None: self.on_new_day(day_key)
        self.last_close=now; self.daily_net+=net
        self.consec = self.consec+1 if net<0 else 0
        self._eval()
    def _eval(self):
        if self.max_trades_day>0 and self.trades_today>=self.max_trades_day:
            self.locked=True; self.reason="MAX_TRADES"
        if self.max_consec>0 and self.consec>=self.max_consec:
            self.locked=True; self.reason="CONSEC_LOSS"
        if self.max_daily_loss>0 and self.daily_net<=-self.max_daily_loss:
            self.locked=True; self.reason="DAILY_LOSS"

def classify_exit(exit_price, initial_tp, last_sl, be_done, trail_active,
                  net_profit, tick_size, is_buy=True, tol_ticks=3):
    """Mirror of CTradeJournal::ClassifyExit.
    Order matters: a filled TP wins, then trailing, then BE, then plain SL.
    TP/SL are matched DIRECTIONALLY: a real TP fill is at or beyond the TP in the
    favourable direction, which absorbs tick granularity and gap-through fills."""
    tol = (tick_size * tol_ticks) if tick_size else 0.0
    if initial_tp:
        if (exit_price >= initial_tp - tol) if is_buy else (exit_price <= initial_tp + tol):
            return "TAKE_PROFIT"
    if trail_active: return "TRAILING_STOP"
    if be_done: return "BREAK_EVEN"
    if last_sl:
        if (exit_price <= last_sl + tol) if is_buy else (exit_price >= last_sl - tol):
            return "STOP_LOSS"
    return "TRAILING_STOP" if net_profit > 0 else "STOP_LOSS"

def metrics_ready(count, window, min_window=None):
    """Mirror of CMarketMetrics::Compute readiness: a PARTIAL window never counts."""
    need = window if min_window is None else min_window
    return count >= 2 and count >= need

def trail_buy(current_sl, bid, trail_dist):
    new_sl = bid - trail_dist
    if new_sl > current_sl: return new_sl
    return current_sl

def trail_sell(current_sl, ask, trail_dist):
    new_sl = ask + trail_dist
    if current_sl == 0 or new_sl < current_sl: return new_sl
    return current_sl

def ema(values, period):
    """Classic EMA; returns list (first value = SMA seed). Needs len>=period."""
    if len(values) < period or period < 2: return []
    k = 2.0 / (period + 1)
    out = [sum(values[:period]) / period]
    for v in values[period:]:
        out.append(v * k + out[-1] * (1 - k))
    return out

def context_gate(closes, ma_period, use_trend, atr_vals, atr_cap,
                 want_buy):
    """Mirror of CMarketContextFilter direction gate.
    closes: list incl. current forming bar; uses last CLOSED bar ([-2]).
    atr_vals: ATR series in points (aligned with closes); uses [-2] too.
    Returns (allowed, reason)."""
    if not use_trend and atr_cap is None:
        return True, "OK"
    if len(closes) < ma_period + 1:
        return False, "CTX_NO_DATA"
    e = ema(closes[:-1], ma_period)  # exclude forming bar
    if not e:
        return False, "CTX_NO_DATA"
    ema_val = e[-1]
    c = closes[-2]
    if atr_cap is not None and atr_vals is not None:
        if len(atr_vals) < 2:
            return False, "CTX_NO_DATA"
        if atr_vals[-2] > atr_cap:
            return False, "VOLATILITY"
    if use_trend:
        if want_buy and c <= ema_val: return False, "CONTEXT_FILTER"
        if not want_buy and c >= ema_val: return False, "CONTEXT_FILTER"
    return True, "OK"

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
