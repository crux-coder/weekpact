"""Draw the W as an AppSurface would draw a card.

SVG has no continuous-corner primitive and round caps read as pills, not as the
app's squircle, so the mark is built as geometry: the stroke is offset into a
closed outline, then every corner is cut back and replaced with the flatter
cubic a `ContinuousRectangleBorder` draws. The card recipe on top of that is
`AppSurface`'s own: fill, a 1px outline of `lerp(fill, black, .28)`, and a solid
offset edge of `lerp(fill, black, .24)` with no blur.
"""
import math
import pathlib
import re

CANVAS = 1024
CUTBACK = 1.45   # Continuous corners run further along the edge than an arc.
PULL = 0.62      # ...and sit flatter through it.


def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def mul(a, k): return (a[0] * k, a[1] * k)
def length(a): return math.hypot(*a)
def unit(a):
    n = length(a)
    return (a[0] / n, a[1] / n)


def offset_side(points, half, sign):
    """Miter-offset a polyline by `half` to one side, ends cut square."""
    out = []
    for i, point in enumerate(points):
        if i == 0:
            d = unit(sub(points[1], point))
            out.append(add(point, mul((-d[1], d[0]), half * sign)))
        elif i == len(points) - 1:
            d = unit(sub(point, points[-2]))
            out.append(add(point, mul((-d[1], d[0]), half * sign)))
        else:
            n1 = unit(sub(point, points[i - 1]))
            n2 = unit(sub(points[i + 1], point))
            n1, n2 = (-n1[1], n1[0]), (-n2[1], n2[0])
            m = unit(add(n1, n2))
            out.append(add(point, mul(m, half * sign / (m[0] * n1[0] + m[1] * n1[1]))))
    return out


def outline(points, width):
    left = offset_side(points, width / 2, 1)
    right = offset_side(points, width / 2, -1)
    return left + right[::-1]


def squircle_path(polygon, radius):
    """Close the polygon, replacing each corner with a continuous-corner cubic."""
    parts = []
    count = len(polygon)
    for i, vertex in enumerate(polygon):
        previous, following = polygon[i - 1], polygon[(i + 1) % count]
        back, forward = sub(previous, vertex), sub(following, vertex)
        cut = min(radius * CUTBACK, length(back) * 0.48, length(forward) * 0.48)
        start = add(vertex, mul(unit(back), cut))
        end = add(vertex, mul(unit(forward), cut))
        c1 = add(start, mul(sub(vertex, start), PULL))
        c2 = add(end, mul(sub(vertex, end), PULL))
        parts.append(f'{"M" if i == 0 else "L"} {start[0]:.1f} {start[1]:.1f}')
        parts.append(f'C {c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} '
                     f'{end[0]:.1f} {end[1]:.1f}')
    return ' '.join(parts) + ' Z'


def channels(colour):
    return [int(colour[i:i + 2], 16) for i in (1, 3, 5)]


def luminance(colour):
    def linear(value):
        v = value / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (linear(c) for c in channels(colour))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def derive(fill, light_amount, dark_amount):
    """AppSurface's own derivation: a pale fill darkens, a dark fill lightens."""
    dark = luminance(fill) < .18
    amount, target = (dark_amount, 255) if dark else (light_amount, 0)
    return '#%02X%02X%02X' % tuple(
        round(c + (target - c) * amount) for c in channels(fill)
    )


def outline_of(fill): return derive(fill, .28, .12)
def edge_of(fill): return derive(fill, .24, .12)


CANVAS_INK = '#2B302C'
LEMON, MINT, INK, CREAM = '#E8D05A', '#8CDCAC', '#191B19', '#F5F6F5'
OUTLINE, EDGE = 9, 22        # 1px and ~3px at the sizes an icon is actually read.
SOLID_W = [(146, 262), (362, 772), (540, 470), (702, 772), (892, 210)]
BACK_TICK = [(140, 280), (358, 778), (566, 350)]
FRONT_TICK = [(474, 540), (676, 786), (896, 214)]


def card(points, width, fill, corner, dx=0, dy=0):
    """One stroke as a card: solid edge under, fill over, derived outline around."""
    path = squircle_path(outline(points, width), corner)
    shift = f' transform="translate({dx},{dy})"' if dx or dy else ''
    return (
        f'    <g{shift}>\n'
        f'      <path d="{path}" fill="{edge_of(fill)}" '
        f'transform="translate(0,{EDGE})"/>\n'
        f'      <path d="{path}" fill="{fill}" stroke="{outline_of(fill)}" '
        f'stroke-width="{OUTLINE}"/>\n'
        f'    </g>\n'
    )


def fit(body, span=0.78):
    """Scale and centre the finished mark so the platform mask never clips it.

    Miter spikes at the W's feet run further than the stroke width predicts, so
    the box is measured off the drawn geometry rather than guessed at.
    """
    numbers = [float(n) for n in re.findall(r'-?\d+\.?\d*', ' '.join(
        re.findall(r'd="([^"]+)"', body)))]
    xs, ys = numbers[0::2], numbers[1::2]
    left, right, top = min(xs), max(xs), min(ys)
    bottom = max(ys) + EDGE  # The offset edge is part of the mark's footprint.
    scale = CANVAS * span / max(right - left, bottom - top)
    dx = (CANVAS - (right - left) * scale) / 2 - left * scale
    dy = (CANVAS - (bottom - top) * scale) / 2 - top * scale
    return (f'    <g transform="translate({dx:.1f},{dy:.1f}) scale({scale:.4f})">\n'
            f'{body}    </g>\n')


def svg(name, comment, background, body):
    pathlib.Path(name).write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'width="{CANVAS}" height="{CANVAS}">\n'
        f'  <!-- {comment} -->\n'
        f'  <rect width="{CANVAS}" height="{CANVAS}" fill="{background}"/>\n'
        f'  <g stroke-linejoin="round">\n{body}  </g>\n</svg>\n'
    )
    print('wrote', name)


svg('F1-w-card.svg',
    'One W, drawn as a card: lemon fill, derived outline, solid offset edge.',
    CANVAS_INK, fit(card(SOLID_W, 158, LEMON, 34)))

svg('F2-w-card-stack.svg',
    'Two ticks, each its own card, the smaller behind — the pact card stack.',
    CANVAS_INK,
    fit(card(BACK_TICK, 142, MINT, 30) + card(FRONT_TICK, 162, LEMON, 34)))

svg('F3-w-on-card.svg',
    'The card face is the icon: lemon fill to the edge, the W in ink on top.',
    LEMON, fit(card(SOLID_W, 158, INK, 34)))


# --- The W mark on its own ------------------------------------------------
#
# Same geometry language as SOLID_W, but with the last stroke driven high so the
# W also reads as a tick. Drawn with `card()`, so its depth is AppSurface's: a
# solid edge straight down, no blur, plus the derived 1px outline.
MARK_W = [(140, 474), (303, 791), (458, 460), (614, 791), (853, 235)]


def squircle_rect(size, curve):
    """A `ContinuousRectangleBorder` as SVG: each corner is a cubic whose two
    control points both sit on the corner itself, which is exactly how Flutter
    draws one."""
    c = curve
    return (f'M 0 {c} C 0 0 0 0 {c} 0 L {size - c} 0 C {size} 0 {size} 0 '
            f'{size} {c} L {size} {size - c} C {size} {size} {size} {size} '
            f'{size - c} {size} L {c} {size} C 0 {size} 0 {size} 0 {size - c} Z')


def bounds(body):
    """The drawn box, including the outline's half-stroke and the offset edge."""
    numbers = [float(n) for n in re.findall(r'-?\d+\.?\d*', ' '.join(
        re.findall(r'd="([^"]+)"', body)))]
    xs, ys = numbers[0::2], numbers[1::2]
    pad = OUTLINE / 2
    return (min(xs) - pad, min(ys) - pad,
            max(xs) + pad, max(ys) + EDGE + pad)


def mark(name, comment, body):
    """The mark alone: no background, viewBox trimmed to the geometry."""
    left, top, right, bottom = bounds(body)
    pathlib.Path(name).write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{left:.0f} {top:.0f} '
        f'{right - left:.0f} {bottom - top:.0f}" role="img" aria-label="W">\n'
        f'  <!-- {comment} -->\n'
        f'  <g stroke-linejoin="round">\n{body}  </g>\n</svg>\n'
    )
    print('wrote', name)


def tile(name, comment, background, curve, body):
    """The mark on the app's squircle, clipped to it the way a card clips."""
    pathlib.Path(name).write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'width="{CANVAS}" height="{CANVAS}">\n'
        f'  <!-- {comment} -->\n'
        f'  <path d="{squircle_rect(CANVAS, curve)}" fill="{background}"/>\n'
        f'  <g stroke-linejoin="round">\n{body}  </g>\n</svg>\n'
    )
    print('wrote', name)


mark('G1-w-squircle.svg',
     'The W alone, drawn as a card: lemon fill, derived outline, solid edge.',
     card(MARK_W, 172, LEMON, 36))

tile('G2-w-squircle-tile.svg',
     'The same W on the app squircle, on the dark canvas.',
     CANVAS_INK, 330, fit(card(MARK_W, 172, LEMON, 36)))
