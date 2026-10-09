#!/usr/bin/env python3
"""Static MQL5 sanity checker (Linux substitute for MetaEditor compile).

Checks:
  * balanced braces/parens per file (noise stripped by a state machine)
  * every #include target resolves to a real file
  * required handlers / safety tokens present
  * no martingale/grid/averaging patterns (per line, so docs wording cannot mask them)
  * include guards are unique
  * every input is wired into the TMBConfig struct
  * structs holding strings are not ZeroMemory'd
"""
import re, sys, pathlib

def strip_noise(t):
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
EA = ROOT / "MQL5/Experts/TickMomentumBurstEA.mq5"
INC = ROOT / "MQL5/Include/TickMomentum"
MT5 = ROOT / "MQL5"

fails = []
def fail(m):
    fails.append(m); print("FAIL:", m)
def ok(m): print("OK:", m)

files = [EA] + sorted(INC.glob("*.mqh"))
raw = {f: f.read_text(encoding="utf-8", errors="replace") for f in files}
blob = "\n".join(raw.values())

# --- 1. balance -----------------------------------------------------
for f in files:
    t = strip_noise(raw[f])
    if t.count("{") != t.count("}"): fail(f"{f.name}: unbalanced braces")
    if t.count("(") != t.count(")"): fail(f"{f.name}: unbalanced parens")
ok("brace/paren balance")

# --- 2. include graph resolves --------------------------------------
for f in files:
    for inc in re.findall(r'#include\s+[<"]([^>"]+)[>"]', raw[f]):
        if inc.startswith("Trade\\") or inc.startswith("Trade/"):
            continue                      # MQL5 standard library
        base = MT5 / inc.replace("\\", "/") if inc.startswith("Experts") is False \
               and ("\\" in inc or "/" in inc) else None
        # includes are written relative to the including file's directory
        cand = (f.parent / inc.replace("\\", "/")).resolve()
        if cand.exists():
            continue
        alt = (MT5 / inc.replace("\\", "/")).resolve()
        if alt.exists():
            continue
        fail(f"{f.name}: include not found: {inc}")
ok("include targets resolve")

# --- 3. unique include guards ---------------------------------------
guards = re.findall(r"#ifndef\s+(__\w+__)", blob)
dupes = {g for g in guards if guards.count(g) > 1}
if dupes: fail(f"duplicate include guards: {sorted(dupes)}")
ok("include guards unique")

# --- 4. required tokens ---------------------------------------------
required_in = ["OnInit", "OnTick", "OnDeinit", "OnTradeTransaction", "OnTester"]
for needle in required_in:
    if needle not in raw[EA]: fail(f"missing EA handler: {needle}")
for needle in ["POSITION_MAGIC", "POSITION_SYMBOL", "SYMBOL_TRADE_TICK_VALUE",
               "SYMBOL_TRADE_STOPS_LEVEL", "InpMagicNumber", "InpMaxSpreadPoints",
               "InpCommissionPerLot"]:
    if needle not in blob: fail(f"missing safety token: {needle}")
ok("handlers + safety tokens present")

# --- 5. no martingale / grid / averaging -----------------------------
forbidden = [r"martingale", r"grid\s*recovery", r"double\s*after\s*loss",
             r"lot\s*\*=\s*2", r"lotmult", r"averag(e|ing)\s*down"]
lines = strip_noise(blob).splitlines()
for pat in forbidden:
    rx = re.compile(pat, re.I)
    for idx, line in enumerate(lines, 1):
        if rx.search(line):
            fail(f"forbidden pattern /{pat}/ in stripped line {idx}: {line.strip()[:70]}")
ok("no martingale/grid/averaging patterns")

# --- 6. magic + symbol filtering ------------------------------------
for token in ["POSITION_MAGIC", "POSITION_SYMBOL", "FindMyPositionTicket"]:
    if token not in blob: fail(f"missing ownership token: {token}")
ok("magic+symbol ownership filtering present")

# --- 7. BE asymmetry + trailing monotonicity ------------------------
for token in ["BreakEvenPriceBuy", "BreakEvenPriceSell"]:
    if token not in blob: fail(f"missing BE side: {token}")
if "curSL < bePrice" not in blob: fail("BE monotonicity marker missing")
if "newSL <= curSL" not in blob and "newSL >= curSL" not in blob:
    fail("trailing monotonicity marker missing")
ok("BE asymmetry + stop monotonicity present")

# --- 8. every input is wired to TMBConfig ----------------------------
ea_text = raw[EA]
inputs = re.findall(r"^input\s+\S+\s+(Inp\w+)", ea_text, re.M)
wired = set(re.findall(r"cfg\.(\w+)\s*=", ea_text))
cfg_block = re.search(r"struct TMBConfig(.*?)\n  \};", blob, re.S)
if not cfg_block:
    fail("TMBConfig struct not found")
    cfg_fields = set()
else:
    body = cfg_block.group(1)
    decl_text = body.split("void")[0]          # field declarations only
    cfg_fields = set(re.findall(r"(\w+)\s*(?:\[[^\]]*\])?\s*;", decl_text))
    cfg_fields -= {"struct", "enum", "const"}
for name in inputs:
    mapped = re.search(rf"cfg\.(\w+)\s*=\s*(?:\([^)]*\)\s*)*{name}\s*;", ea_text)
    if mapped and mapped.group(1) not in cfg_fields:
        fail(f"input {name} maps to unknown TMBConfig field cfg.{mapped.group(1)}")
    elif not mapped:
        fail(f"input {name} is never assigned into TMBConfig")
ok(f"all {len(inputs)} inputs wired into TMBConfig")

# --- 9. no ZeroMemory on structs containing strings ------------------
struct_re = re.compile(r"struct\s+(\w+)\s*\{(.*?)\n  \};", re.S)
str_structs = {n for n, b in struct_re.findall(blob) if re.search(r"^\s+string\s+\w+;", b, re.M)}
for name in sorted(str_structs):
    if re.search(rf"ZeroMemory\(\s*{name}\b", blob):
        fail(f"ZeroMemory on string-bearing struct {name} (use its Reset())")
ok("no ZeroMemory on string-bearing structs")

if fails:
    print(f"\n{len(fails)} static check(s) FAILED")
    sys.exit(1)
print("\nAll static checks passed")