"""Rebuild the v2 contact sheet from the SVGs in this folder."""
import pathlib

HERE = pathlib.Path(__file__).parent
NOTES = {
 'F3-w-on-card.svg': ('Card face', 'The icon is the card: lemon fill to the edge, the W in ink on it, exactly the pairing the Check in button already uses.'),
 'F1-w-card.svg': ('Card mark', 'Canvas full bleed, the W itself drawn as a card — lemon fill, derived outline, solid offset edge.'),
 'F2-w-card-stack.svg': ('Card stack', 'Two ticks, each its own card, the smaller mint one behind. The overlap reads the way the pact card stack does.'),
 'E2-w-charcoal-solid.svg': ('Round caps', 'The previous cut, kept for comparison: pill terminals and no card treatment.'),
 'B-w-monogram.svg': ('Sky — cream band', 'The first colourway.'),
}
MASKS = [('squircle', 'iOS'), ('circle', 'Android')]

def instance(inner, size, cls=''):
    return f'<svg class="ico {cls}" viewBox="0 0 1024 1024" width="{size}" height="{size}">{inner}</svg>'

cards = []
for name, (title, note) in NOTES.items():
    inner = (HERE / name).read_text().split('>', 1)[1].rsplit('</svg>', 1)[0]
    masks = ''.join(
        f'<div class="s"><div class="wrap dark">{instance(inner, 96, cls)}</div><span>{label}</span></div>'
        for cls, label in MASKS)
    cards.append(f'''<section class="card">
  <div class="hero">{instance(inner, 220, 'squircle')}</div>
  <div class="sizes">
    <div class="s"><div class="wrap light">{instance(inner, 120, 'squircle')}</div><span>120</span></div>
    <div class="s"><div class="wrap light">{instance(inner, 60, 'squircle')}</div><span>60</span></div>
    <div class="s"><div class="wrap dark">{instance(inner, 40, 'squircle')}</div><span>40</span></div>
    {masks}
  </div>
  <h2>{title}</h2>
  <p>{note}</p>
  <code>{name}</code>
</section>''')

(HERE / 'index.html').write_text(f'''<!doctype html>
<meta charset="utf-8"><title>WeekPact icon concepts v2</title>
<style>
  body {{ margin:0; padding:48px; background:#ECEDEA; color:#191B19;
         font:16px/1.5 -apple-system,BlinkMacSystemFont,sans-serif; }}
  h1 {{ font-size:28px; margin:0 0 8px; }}
  .lede {{ margin:0 0 40px; max-width:62ch; color:#4a504a; }}
  .grid {{ display:grid; gap:28px; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)); }}
  .card {{ background:#F5F6F5; border:2px solid #191B19; border-radius:24px; padding:24px; }}
  .hero {{ display:flex; justify-content:center; margin-bottom:20px; }}
  .sizes {{ display:flex; align-items:flex-end; gap:18px; flex-wrap:wrap; }}
  .s {{ display:flex; flex-direction:column; align-items:center; gap:6px; }}
  .s span {{ font-size:11px; color:#6b716b; }}
  .wrap {{ padding:10px; border-radius:12px; }}
  .light {{ background:#DDDFD7; }} .dark {{ background:#2B302C; }}
  .ico {{ display:block; }}
  .squircle {{ clip-path: inset(0 round 22.5%); }}
  .circle {{ clip-path: circle(50%); }}
  h2 {{ font-size:18px; margin:20px 0 6px; }}
  p {{ margin:0 0 12px; color:#4a504a; font-size:14px; }}
  code {{ font-size:12px; color:#6b716b; }}
</style>
<h1>WeekPact icon concepts &mdash; v2</h1>
<p class="lede">Card recipe throughout: fill, a <code>lerp(fill, black, .28)</code> outline, a solid <code>.24</code> offset edge and continuous squircle corners, with a dark fill lightening by <code>.12</code> instead. Every one is full bleed: the colour runs to the edge and the platform does the
rounding, so no margin ships inside the icon. Judge them at 40&nbsp;px, and check the
iOS/Android mask row &mdash; a circular mask eats the corners.</p>
<div class="grid">{''.join(cards)}</div>
''')
print('Wrote index.html')
