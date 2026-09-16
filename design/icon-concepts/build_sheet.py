"""Rebuild the concept contact sheet from the SVGs in this folder."""
import pathlib, re

HERE = pathlib.Path(__file__).parent
NOTES = {
 '01-double-tick.svg': ('Double tick', 'Keeps the double check but flattens it into the app’s outlined-sticker style. Two ticks = you and your crew.'),
 '02-week-ring.svg': ('Week ring', 'Seven day segments, five kept. The ring carries progress, the tick carries check-in.'),
 '03-crew-check.svg': ('Crew check', 'A huddle with one tick across it. The most literal "accountability with people".'),
 '04-pact-knot.svg': ('Pact knot', 'Two links holding each other — the pact itself. No tick, so it looks like nothing else in the folder.'),
 '05-keep-up.svg': ('Keep up', 'A tick rising over the week’s bars. Leans on the app name and on streaks.'),
 '06-tickbox.svg': ('Tick box', 'The checkbox from the Today screen with the tick bursting out of it. Loudest at 40px.'),
}

def instance(inner, size, tag):
    # Element ids are per-file, so scope them per copy to avoid collisions.
    body = re.sub(r'(id="|url\(#)([\w-]+)', lambda m: m.group(1) + m.group(2) + tag, inner)
    return f'<svg class="ico" viewBox="0 0 1024 1024" width="{size}" height="{size}">{body}</svg>'

cards = []
for name, (title, note) in NOTES.items():
    inner = (HERE / name).read_text().split('>', 1)[1].rsplit('</svg>', 1)[0]
    key = name.split('-')[0]
    cards.append(f'''<section class="card">
  <div class="hero">{instance(inner, 224, key + 'a')}</div>
  <div class="sizes">
    <div class="s"><div class="wrap light">{instance(inner, 120, key + 'b')}</div><span>120</span></div>
    <div class="s"><div class="wrap light">{instance(inner, 60, key + 'c')}</div><span>60</span></div>
    <div class="s"><div class="wrap dark">{instance(inner, 40, key + 'd')}</div><span>40</span></div>
  </div>
  <h2>{title}</h2>
  <p>{note}</p>
  <code>{name}</code>
</section>''')

head = (HERE / 'index.html').read_text().split('<div class="grid">', 1)[0]
(HERE / 'index.html').write_text(head + '<div class="grid">\n' + '\n'.join(cards) + '\n</div>\n')
print(f'Rebuilt the sheet from {len(cards)} concepts.')
