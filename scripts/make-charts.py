#!/usr/bin/env python3
"""Generates the SVG figures under docs/assets from the numbers recorded in the docs.
Static SVG (GitHub renders it in Markdown); palette from a validated reference set."""
import math, os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "assets")
os.makedirs(OUT, exist_ok=True)

SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e6e5e1"
BLUE, ORANGE, AQUA, YELLOW = "#2a78d6", "#eb6834", "#1baf7a", "#eda100"
FONT = "font-family=\"-apple-system, 'Helvetica Neue', Arial, sans-serif\""

def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" {FONT}>'
            f'<rect width="{w}" height="{h}" fill="{SURFACE}" rx="8"/>{body}</svg>')

def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def text(x, y, s, size=13, color=INK, anchor="start", weight="normal", extra=""):
    s = esc(s)
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" text-anchor="{anchor}" font-weight="{weight}" {extra}>{s}</text>'

def bar_h(x, y, w, h, color):
    """Horizontal bar: square at the baseline (left), 4px rounded data end (right)."""
    w = max(w, 4)
    return (f'<path d="M{x},{y} h{w-4} a4,4 0 0 1 4,4 v{h-8} a4,4 0 0 1 -4,4 h-{w-4} z" fill="{color}"/>')

def bar_v(x, y_base, w, h, color):
    """Vertical bar growing up from y_base with a 4px rounded top."""
    h = max(h, 4)
    top = y_base - h
    return (f'<path d="M{x},{y_base} v-{h-4} a4,4 0 0 1 4,-4 h{w-8} a4,4 0 0 1 4,4 v{h-4} z" fill="{color}"/>')

def write(name, content):
    with open(os.path.join(OUT, name), "w") as f: f.write(content)
    print("wrote", name)

# 1. Results at a glance: four stat tiles + RSS sparkline -------------------------------------
def glance():
    W, H = 960, 250
    tiles = [
        ("+0.05 s", "CPU time added, 50 s idle", "one 1 ms window check per second"),
        ("84 MB", "resident memory, stable", "±0.2 MB across the run"),
        ("563 / 563", "automated checks passing", "17 XCTest + 43 self-test + 503 scenario"),
        ("29 fixed", "verified review defects", "two adversarial reviews, duplicates merged"),
    ]
    b = [text(20, 30, "QuietDesk: results at a glance", 16, INK, weight="600")]
    tw = (W - 40 - 3 * 16) / 4
    for i, (big, label, sub) in enumerate(tiles):
        x = 20 + i * (tw + 16)
        b.append(f'<rect x="{x}" y="50" width="{tw}" height="150" rx="10" fill="#ffffff" stroke="{GRID}"/>')
        b.append(text(x + 16, 110, big, 40, INK, weight="600", extra='font-variant-numeric="tabular-nums"'))
        b.append(text(x + 16, 140, label, 14, INK))
        b.append(text(x + 16, 162, sub, 12, INK2))
    # sparkline of RSS (MB) over the 60 s run inside tile 2
    rss = [84.2, 84.6, 84.4, 84.3, 84.3, 84.3, 84.3, 84.3, 84.3, 84.3, 84.3]
    x0 = 20 + (tw + 16) + 16; y0 = 190; wpx = tw - 32
    pts = [(x0 + k * wpx / (len(rss) - 1), y0 - (v - 84.0) * 12) for k, v in enumerate(rss)]
    b.append('<polyline points="' + " ".join(f"{px:.1f},{py:.1f}" for px, py in pts) + f'" fill="none" stroke="{BLUE}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>')
    b.append(text(20, 228, "Measured on macOS 26.6.2 (scripts/measure-idle.sh); details in docs/FEASIBILITY.md, E12 and E15.", 12, INK2))
    write("results-at-a-glance.svg", svg(W, H, "".join(b)))

# 2. Idle measurement: two panels (CPU time, RSS) over time -----------------------------------
def idle():
    W, H = 960, 300
    t = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
    cpu = [0.25, 0.26, 0.27, 0.27, 0.28, 0.28, 0.28, 0.29, 0.29, 0.30, 0.30]
    rss = [84.2, 84.6, 84.4, 84.3, 84.3, 84.3, 84.3, 84.3, 84.3, 84.3, 84.3]
    b = [text(20, 30, "Idle behaviour over a 60-second run (release build, desktop taken over, no interaction)", 15, INK, weight="600")]
    def panel(x0, title, ys, ymin, ymax, unit, color, fmt):
        pw, ph, top, bottom = 420, 170, 70, 250
        b.append(text(x0, 58, title, 13, INK2))
        for k in range(4):
            gy = bottom - k * (bottom - top) / 3
            b.append(f'<line x1="{x0}" y1="{gy:.1f}" x2="{x0+pw}" y2="{gy:.1f}" stroke="{GRID}" stroke-width="1"/>')
            b.append(text(x0 - 6, gy + 4, fmt(ymin + k * (ymax - ymin) / 3), 11, INK2, anchor="end"))
        pts = [(x0 + (tt - 0) * pw / 60, bottom - (v - ymin) * (bottom - top) / (ymax - ymin)) for tt, v in zip(t, ys)]
        b.append('<polyline points="' + " ".join(f"{px:.1f},{py:.1f}" for px, py in pts) + f'" fill="none" stroke="{color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>')
        for px, py in pts:
            b.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="6" fill="{SURFACE}"/><circle cx="{px:.1f}" cy="{py:.1f}" r="4" fill="{color}"/>')
        for tt in (0, 10, 20, 30, 40, 50, 60):
            b.append(text(x0 + tt * pw / 60, bottom + 18, f"{tt}s", 11, INK2, anchor="middle"))
        px, py = pts[-1]
        b.append(text(px - 8, py - 12, fmt(ys[-1]) + unit, 12, INK, anchor="end", weight="600"))
    panel(70, "Cumulative CPU time (s): one 1 ms window check per second", cpu, 0, 1.0, " s", BLUE, lambda v: f"{v:.2f}")
    panel(530, "Resident memory (MB)", rss, 60, 100, " MB", ORANGE, lambda v: f"{v:.0f}")
    b.append(text(20, 285, "Samples from ps every 5 s. Source: docs/FEASIBILITY.md E15; reproduce with scripts/measure-idle.sh 60.", 12, INK2))
    write("idle-measurement.svg", svg(W, H, "".join(b)))

# 3. Code review findings by lens ---------------------------------------------------------------
def review():
    rows = [("File safety", 4, 4, 0), ("Events & focus", 2, 6, 0), ("Idle resources", 0, 8, 1),
            ("Restore safety", 2, 6, 0), ("Layout & model", 4, 4, 0), ("Module integration", 3, 5, 0)]
    W, H = 960, 330
    b = [text(20, 30, "Adversarial code review: findings per lens, after independent verification", 15, INK, weight="600")]
    x0, scale, bh = 200, 60, 20
    for i, (name, conf, minor, rej) in enumerate(rows):
        y = 60 + i * 36
        b.append(text(x0 - 12, y + 15, name, 13, INK, anchor="end"))
        x = x0
        for val, color in ((conf, BLUE), (minor, AQUA), (rej, ORANGE)):
            if val:
                b.append(bar_h(x, y, val * scale - 2, bh, color))
                b.append(text(x + val * scale / 2 - 1, y + 15, str(val), 12, "#ffffff", anchor="middle", weight="600"))
                x += val * scale
    ly = 60 + len(rows) * 36 + 10
    for k, (label, color) in enumerate((("Confirmed and fixed (15)", BLUE), ("Minor, triaged (33)", AQUA), ("Rejected by verifier (1)", ORANGE))):
        lx = x0 + k * 230
        b.append(f'<rect x="{lx}" y="{ly}" width="12" height="12" rx="3" fill="{color}"/>')
        b.append(text(lx + 18, ly + 11, label, 12, INK))
    b.append(text(20, H - 15, "Six reviewers, one lens each; every non-minor claim went to a skeptic told to assume it false. Source: docs/evidence/code-review.md.", 12, INK2))
    write("review-findings.svg", svg(W, H, "".join(b)))

# 4. Research: sources and verdicts -------------------------------------------------------------
def research():
    W, H = 960, 300
    b = [text(20, 30, "Feasibility research: 290 findings across 8 topics, each claim re-checked against its source", 15, INK, weight="600")]
    def panel(x0, title, items, color):
        pw, bottom, top = 400, 230, 80
        mx = max(v for _, v in items)
        b.append(text(x0, 60, title, 13, INK2))
        n = len(items); slot = pw / n
        for k, (label, v) in enumerate(items):
            bw = min(24, slot - 16)
            x = x0 + k * slot + (slot - bw) / 2
            h = (bottom - top) * v / mx
            b.append(bar_v(x, bottom, bw, h, color))
            b.append(text(x + bw / 2, bottom - h - 8, str(v), 12, INK, anchor="middle", weight="600"))
            b.append(text(x + bw / 2, bottom + 18, label, 11, INK2, anchor="middle"))
        b.append(f'<line x1="{x0}" y1="{bottom}" x2="{x0+pw}" y2="{bottom}" stroke="{GRID}" stroke-width="1"/>')
    panel(60, "By source kind", [("Apple primary", 204), ("Community", 58), ("None found", 28)], BLUE)
    panel(520, "Verifier verdict on cited sources", [("Supported", 219), ("Partially", 48), ("Not supported", 2), ("Could not fetch", 3)], BLUE)
    b.append(text(20, H - 15, "16 agents, 1,336 tool calls, 26 minutes. \"None found\" means the researcher said so instead of guessing. Source: docs/evidence/research.md.", 12, INK2))
    write("research-verification.svg", svg(W, H, "".join(b)))

# 5. Grid calibration -----------------------------------------------------------------------
def calibration():
    W, H = 960, 320
    b = [text(20, 30, "Grid calibration: cell size vs Finder's grid-spacing value (icon 36, text 12)", 15, INK, weight="600")]
    x0, pw, top, bottom = 80, 800, 70, 250
    smin, smax, ymin, ymax = 1, 100, 40, 200
    def X(s): return x0 + (s - smin) * pw / (smax - smin)
    def Y(v): return bottom - (v - ymin) * (bottom - top) / (ymax - ymin)
    for v in (50, 100, 150, 200):
        b.append(f'<line x1="{x0}" y1="{Y(v):.1f}" x2="{x0+pw}" y2="{Y(v):.1f}" stroke="{GRID}"/>')
        b.append(text(x0 - 8, Y(v) + 4, f"{v} pt", 11, INK2, anchor="end"))
    for s in (1, 26, 50, 75, 100):
        b.append(text(X(s), bottom + 18, f"spacing {s}", 11, INK2, anchor="middle"))
    width = lambda s: 36 + 13 + 1.36 * s
    height = lambda s: 36 + 30 + 0.64 * (s - 1)
    for fn, color, label in ((width, BLUE, "cell width"), (height, ORANGE, "cell height")):
        pts = " ".join(f"{X(s):.1f},{Y(fn(s)):.1f}" for s in range(1, 101))
        b.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="2" stroke-linejoin="round"/>')
        b.append(text(X(100) - 4, Y(fn(100)) - 10, label, 12, INK, anchor="end", weight="600"))
    for s, w, h in ((1, 50, 66), (26, 84, 82)):
        for v, color in ((w, BLUE), (h, ORANGE)):
            b.append(f'<circle cx="{X(s):.1f}" cy="{Y(v):.1f}" r="7" fill="{SURFACE}"/><circle cx="{X(s):.1f}" cy="{Y(v):.1f}" r="5" fill="{color}"/>')
        b.append(text(X(s) + 12, Y(h) + (16 if s == 1 else -12), f"measured {w}×{h} pt", 12, INK))
    b.append(text(20, H - 15, "Dots: cells measured from Finder screenshots at spacing 1 and 26. Lines: the linear formula used between and beyond them (E7, E13).", 12, INK2))
    write("grid-calibration.svg", svg(W, H, "".join(b)))

# 6. Workflows: agents and tokens ----------------------------------------------------------
def workflows():
    W, H = 960, 330
    rows = [("Feasibility research", 16, 2.28), ("Module implementation", 11, 1.48), ("Code review (5 lenses)", 18, 2.13),
            ("Code review (integration)", 4, 0.60), ("Evidence documentation", 8, 1.44)]
    b = [text(20, 30, "The five agent workflows: how much work each one was", 15, INK, weight="600")]
    def panel(x0, title, idx, color, fmt, scale):
        b.append(text(x0 + 180, 58, title, 13, INK2))
        for i, row in enumerate(rows):
            y = 72 + i * 36
            b.append(text(x0 + 170, y + 15, row[0], 12, INK, anchor="end"))
            v = row[idx]
            b.append(bar_h(x0 + 180, y, v * scale, 20, color))
            b.append(text(x0 + 180 + v * scale + 8, y + 15, fmt(v), 12, INK))
    panel(20, "Agents", 1, BLUE, lambda v: str(v), 12)
    panel(500, "Tokens (millions)", 2, ORANGE, lambda v: f"{v:.2f} M", 90)
    b.append(text(20, H - 15, "Agents include the verifiers. The lead agent's own work is not counted. Source: docs/CASE-STUDY.md §6.", 12, INK2))
    write("workflows.svg", svg(W, H, "".join(b)))

# 7. Window layers diagram ------------------------------------------------------------------
def layers():
    W, H = 960, 360
    layers = [
        ("Application windows", "normal level (0) and above", "#f2f1ee", INK2),
        ("QuietDesk icon panel", "desktop-icon level + 1: draws icons and labels; keyboard focus without activating", BLUE, "#ffffff"),
        ("QuietDesk shield panel", "desktop-icon level + 1, under the icon panel: bitmap-free, owns wallpaper clicks", "#86b6ef", INK),
        ("WindowManager click-catcher", "desktop-icon level, only while items are hidden: a wallpaper click re-shows Finder's icons", "#f2f1ee", INK2),
        ("Finder desktop icons window", "desktop-icon level (-2147483603): emptied by the Show Items setting", "#f2f1ee", INK2),
        ("Wallpaper", "desktop level (-2147483623)", "#f2f1ee", INK2),
    ]
    b = [text(20, 30, "Where QuietDesk sits: the stack of window levels, top to bottom", 15, INK, weight="600")]
    for i, (name, note, fill, ink) in enumerate(layers):
        y = 50 + i * 48
        b.append(f'<rect x="20" y="{y}" width="{W-40}" height="40" rx="8" fill="{fill}" stroke="{GRID}"/>')
        b.append(text(36, y + 25, name, 13, ink, weight="600"))
        b.append(text(300, y + 25, note, 12, ink))
    b.append(text(20, H - 15, "Higher levels are closer to you. Verified with window-server hit tests on macOS 26.6.2 (E4, E8, E10, E11).", 12, INK2))
    write("window-layers.svg", svg(W, H, "".join(b)))

for fn in (glance, idle, review, research, calibration, workflows, layers): fn()
