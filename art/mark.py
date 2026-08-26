#!/usr/bin/env python3
"""OpenSprinkler add-on mark.

The spray is measured from the OpenSprinkler wordmark: a symmetric pair of
ballistic droplet arcs that rise from the nozzle, peak around dx=+/-28 and fall
again by dx=+/-42, the droplets shrinking as they travel. Source measurements,
in px relative to the nozzle dot at (69.8, 38.3) of the 140x86 wordmark:

    nozzle   (   0.0,   0.0)  r 3.7
    pair 1   (+/- 6.4,  -9.0)  r 4.0
    pair 2   (+/-14.5, -19.1)  r 3.0
    pair 3   (+/-27.8, -25.5)  r 2.5
    pair 4   (+/-41.6, -21.9)  r 2.0

Two deliberate departures, both for legibility as a standalone mark:

  X_SQUEEZE   the true arc is 2.7:1, which leaves a square icon mostly empty
              and shrinks the droplets. 0.80 fills the canvas while keeping the
              droplets distinct -- below about 0.7 the inner pair merges into a
              blob and the airy spray reading is lost.
  STEM        the wordmark's spray sits above the letter "i", which is what
              makes it read as a sprinkler. Without a body it reads as a
              scattered V, so the mark carries a shortened, slightly wider
              version of that stem in the same teal.
"""
import subprocess, sys

TEAL = "#6fccc0"   # sampled from the wordmark
DARK = "#1d1d1d"   # sampled from the wordmark

DROPS = [(0.0, 0.0, 3.7), (6.4, -9.0, 4.0), (14.5, -19.1, 3.0),
         (27.8, -25.5, 2.5), (41.6, -21.9, 2.0)]

STEM_TOP, STEM_FULL = 7.2, 26.0
STEM_LEN, STEM_W = 0.70, 10.0
X_SQUEEZE_SQUARE, X_SQUEEZE_WIDE = 0.80, 1.00


def svg(w, h, frac, xsq):
    top = -(25.5 + 2.5)
    s_bot = STEM_TOP + STEM_FULL * STEM_LEN
    mw = 2 * (41.6 * xsq + 2.0)
    scale = (w * frac) / mw
    cx = w / 2
    oy = h / 2 - (top + (s_bot - top) / 2) * scale
    p = [f'<rect width="{w}" height="{h}" fill="{DARK}"/>',
         f'<rect x="{cx - STEM_W / 2 * scale:.2f}" y="{oy + STEM_TOP * scale:.2f}" '
         f'width="{STEM_W * scale:.2f}" height="{(s_bot - STEM_TOP) * scale:.2f}" '
         f'rx="{STEM_W / 2 * scale:.2f}" fill="{TEAL}"/>']
    for dx, dy, r in DROPS:
        for x in ([0.0] if dx == 0 else [-dx * xsq, dx * xsq]):
            p.append(f'<circle cx="{cx + x * scale:.2f}" cy="{oy + dy * scale:.2f}" '
                     f'r="{r * scale:.2f}" fill="{TEAL}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}">' + "".join(p) + '</svg>')


def render(w, h, frac, xsq, out):
    open(out + ".svg", "w").write(svg(w, h, frac, xsq))
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h),
                    out + ".svg", "-o", out + ".png"], check=True)


if __name__ == "__main__":
    d = sys.argv[1]
    render(256, 256, 0.86, X_SQUEEZE_SQUARE, f"{d}/icon")
    render(500, 200, 0.62, X_SQUEEZE_WIDE,   f"{d}/logo")
    print("rendered icon.png (256x256) and logo.png (500x200)")
