#!/usr/bin/env python3
"""Draws docs/images/how-it-works-{en,ko}.svg (and .png if rsvg-convert exists).
Usage: python3 scripts/make-diagram.py"""
import shutil, subprocess, pathlib

T = {
 "en": dict(
  t1="Before: macOS default \"1680×1050\" (not HiDPI)",
  a1="macOS draws", a2="1680×1050 px", a3="1x, no Retina",
  b1="Cable", b2="1680×1050",
  c1="Monitor scaler", c2="stretches to 2560×1600", c3="×1.52, not a whole number",
  d1="Blurry text", d2="soft, smeared edges",
  t2="With PortableHiDPI: \"1680×1050\" HiDPI",
  e1="Virtual display", e2="3360×2100 px", e3="looks like 1680×1050 (2x)",
  f1="Hardware mirror", f2="GPU scales down", f3="3360 → 2560 (×0.76)",
  g1="Real monitor", g2="driven at 2560×1600", g3="panel's own pixels, 1:1",
  h1="Sharp text", h2="same size, Retina-like",
  note="Shrinking a 2x image keeps detail; stretching a 1x image cannot add it."),
 "ko": dict(
  t1="기존: macOS 기본 \"1680×1050\" (HiDPI 아님)",
  a1="macOS가 그림", a2="1680×1050 픽셀", a3="1배, 레티나 아님",
  b1="케이블", b2="1680×1050",
  c1="모니터 스케일러", c2="2560×1600으로 늘림", c3="1.52배, 정수배가 아님",
  d1="흐릿한 글씨", d2="획 경계가 번짐",
  t2="PortableHiDPI: \"1680×1050\" HiDPI",
  e1="가상 디스플레이", e2="3360×2100 픽셀", e3="1680×1050처럼 보임 (2배)",
  f1="하드웨어 미러링", f2="GPU가 축소", f3="3360 → 2560 (0.76배)",
  g1="실제 모니터", g2="2560×1600으로 출력", g3="패널 픽셀 그대로 1:1",
  h1="선명한 글씨", h2="크기는 같고 레티나처럼",
  note="2배로 그린 걸 줄이면 디테일이 남고, 1배를 늘리면 없는 디테일이 생기지 않는다."),
}

def box(x, y, w, h, lines, fill, stroke, bold_first=True):
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill}" stroke="{stroke}" stroke-width="2"/>']
    cy = y + h / 2 - (len(lines) - 1) * 11
    for i, s in enumerate(lines):
        weight = 700 if (i == 0 and bold_first) else 400
        size = 17 if i == 0 else 14
        out.append(f'<text x="{x + w/2}" y="{cy + i*22}" text-anchor="middle" dominant-baseline="middle" font-size="{size}" font-weight="{weight}" fill="#1f2328">{s}</text>')
    return "\n".join(out)

def arrow(x1, x2, y):
    return f'<line x1="{x1}" y1="{y}" x2="{x2 - 8}" y2="{y}" stroke="#57606a" stroke-width="2.5"/><path d="M{x2} {y} l-10 -6 v12 z" fill="#57606a"/>'

def svg(t):
    W, bw, bh, gap, x0 = 1000, 200, 96, 40, 30
    xs = [x0 + i * (bw + gap) for i in range(4)]
    p = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="400" viewBox="0 0 {W} 400" font-family="Apple SD Gothic Neo, Noto Sans KR, -apple-system, Helvetica, Arial, sans-serif">',
         f'<rect width="{W}" height="400" fill="#ffffff"/>']
    y1, y2 = 60, 230
    p.append(f'<text x="{x0}" y="{y1 - 22}" font-size="19" font-weight="700" fill="#cf222e">{t["t1"]}</text>')
    rows1 = [[t["a1"], t["a2"], t["a3"]], [t["b1"], t["b2"]], [t["c1"], t["c2"], t["c3"]], [t["d1"], t["d2"]]]
    for i, r in enumerate(rows1):
        bad = i == 3
        p.append(box(xs[i], y1, bw, bh, r, "#ffebe9" if bad else "#f6f8fa", "#cf222e" if bad else "#d0d7de"))
        if i < 3: p.append(arrow(xs[i] + bw + 4, xs[i + 1] - 4, y1 + bh / 2))
    p.append(f'<text x="{x0}" y="{y2 - 22}" font-size="19" font-weight="700" fill="#1a7f37">{t["t2"]}</text>')
    rows2 = [[t["e1"], t["e2"], t["e3"]], [t["f1"], t["f2"], t["f3"]], [t["g1"], t["g2"], t["g3"]], [t["h1"], t["h2"]]]
    for i, r in enumerate(rows2):
        good = i == 3
        accent = i in (0, 1)
        fill = "#dafbe1" if good else ("#ddf4ff" if accent else "#f6f8fa")
        stroke = "#1a7f37" if good else ("#0969da" if accent else "#d0d7de")
        p.append(box(xs[i], y2, bw, bh, r, fill, stroke))
        if i < 3: p.append(arrow(xs[i] + bw + 4, xs[i + 1] - 4, y2 + bh / 2))
    p.append(f'<text x="{W/2}" y="372" text-anchor="middle" font-size="15" fill="#57606a">{t["note"]}</text>')
    p.append("</svg>")
    return "\n".join(p)

out = pathlib.Path(__file__).resolve().parent.parent / "docs/images"
out.mkdir(parents=True, exist_ok=True)
for lang, t in T.items():
    f = out / f"how-it-works-{lang}.svg"
    f.write_text(svg(t), encoding="utf-8")
    if shutil.which("rsvg-convert"):
        subprocess.run(["rsvg-convert", "-z", "2", "-o", str(f.with_suffix(".png")), str(f)], check=True)
    print(f)
