# Crew switching concepts

Five alternatives to the `YOUR CREW ⌄` dropdown, drawn on the current dark Home screen.
Open `index.html` — every phone is live, so you can drag, tap and hold the header rather
than read a description of the gesture.

| Concept | Gesture | Shape of the idea |
| --- | --- | --- |
| Crew rail | Swipe the header | The name slides like a tape, dots on the right |
| Folder tabs | Tap a tab | Crews as binder dividers above the header |
| Card fan | Tap the header | The crews deal out as cards showing today's state |
| Thumb dial | Press and hold | Crews arc out around your thumb; slide and release |
| Crew deck | Flick the card away | The header is a deck; the top card flies off |

## What shipped

A hybrid of **thumb dial** and **card fan**: hold the header and the crew *cards* deal
out under your thumb, slide onto one and release. A plain tap leaves the hand dealt so
the fan is still reachable without the gesture. Built in `lib/src/crew/crew_fan.dart`
and `lib/src/crew/crew_switcher.dart`.

## Notes for picking one

- **Rail** and **deck** both use a horizontal drag, which the pact stack already owns on
  the same screen. Either one means deciding which zone wins a sideways swipe.
- **Tabs** is the only one that shows every crew without an extra gesture, and the only
  one with room for a per-crew notification dot.
- **Fan** and **dial** are still menus. The fan is the most informative (counts and
  progress per crew), the dial is the fastest once learned but invisible until held —
  it needs the plain tap to keep opening something.
- All five assume two to four crews. Past five, only tabs (scrolling) and fan hold up.

The mockups use sample crews — Hangboardasi, Early Birds, Sunday Run — and the palette
from `lib/src/theme/weekpact_theme.dart`.
