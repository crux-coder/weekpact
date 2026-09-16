# App icon concepts

Six replacements for `assets/branding/weekpact-icon.png`. Open `index.html` to see them
all at 120/60/40 px, which is where icons actually get judged.

Two things they all change about the current icon:

- **Full bleed.** The current artwork is a green squircle floating on a dark square, so
  iOS rounds the corners of the dark square and the margin ships as part of the icon.
  These fill the whole canvas and let the platform mask it.
- **No 3D.** The claymorphic render doesn't match the app, which is flat pastel fills
  behind thick black outlines. These use the same ink, the same palette, the same
  chunky rounded geometry as the Today screen.

| File | Idea |
| --- | --- |
| `01-double-tick.svg` | The current double check, flattened and re-cut |
| `02-week-ring.svg` | Seven day segments, five kept, tick in the middle |
| `03-crew-check.svg` | A huddle of three with one tick across it |
| `04-pact-knot.svg` | Two interlocking links — the pact, no tick at all |
| `05-keep-up.svg` | A tick rising over the week's bars |
| `06-tickbox.svg` | The Today screen's checkbox, tick bursting out |

## Shipping one

```bash
python3 design/icon-concepts/rasterize.py design/icon-concepts/06-tickbox.svg assets/branding/weekpact-icon.png
python3 tool/generate_app_icons.py
```

`rasterize.py` draws the SVG through QuickLook (macOS has no SVG rasteriser on the
command line) and strips the alpha channel, because `generate_app_icons.py` asserts every
platform icon is opaque. Run `python3 build_sheet.py` after editing any SVG to refresh
`index.html`.
