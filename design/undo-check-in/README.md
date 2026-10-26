# Undo check-in — ideas

Eight ways to take a check-in back. Open `index.html`; every card is live.

What ships today (`_CompletedCheckIn` in `lib/src/home/today_widgets.dart`): an underlined
**Undo** at the right end of the cream done bar, which since a063315 asks first through a
centred `AppDialog`. That is safe, but even a quick fix for a mis-tap costs two taps and a modal.

| Design | How undo works | Confirm? | Change size |
| --- | --- | --- | --- |
| A · Today | Link, then a dialog | Dialog | — |
| B · Undo toast | Toast with a 5s ring, right after you check in | None (time-boxed) | Small |
| C · Hold to undo | Hold the done bar for 0.8s while a fill sweeps back | The hold itself | Small |
| D · Tap twice | First tap arms the bar for 3s, second tap undoes | Inline | Small |
| E · Swipe to undo | Drag the done bar left past halfway | The drag itself | Medium |
| F · Overflow menu | ⋯ opens a sheet with photo, story and undo actions | The sheet | Medium |
| G · Undo window | Undo open for 5 min after checking in, then "Locked in" | None | Medium (server rule) |
| H · Tick toggle | A corner checkbox does both check in and undo | Toast from B | Large |

**B + C** together look strongest. The toast handles the common case, a mis-tap right after
checking in, with one tap and no dialog. Hold-to-undo on the bar handles a later change of mind
without leaving a bare link next to the check-in it takes back.

**E** fights the horizontal swipe deck on Home. **G** is as much a product rule as a UI choice:
it stops anyone quietly editing their week after the crew has seen it.
