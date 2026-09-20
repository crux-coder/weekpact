# Home pact cards — ideas

Six ways to cut the front card on Home down. Open `index.html`.

What ships today (`_PactCard` in `lib/src/home/today_widgets.dart`): a title, the pact icon, an
84pt `3 / 5`, one segment per promised day, and a full-width check-in button — all inside 200px.
The number and the segment bar are the same fact told twice, and the icon is positioned off the
top-right corner attached to nothing. Every idea below **removes** something rather than
rearranging it.

| Design | Removes | New data | Change size |
| --- | --- | --- | --- |
| A · One fact | The 84pt number — the segments are the count | None | Small |
| B · The number | The segment bar — the number is the count | None | Small |
| C · Ring row | The deck; 96px rows, three pacts visible at once | None | Large (Home's layout) |
| D · Rows | The colour block; 66px a pact, five visible | None | Large |
| E · Card is the button | The button — the card is the tap target, state is the fill | None | Medium |
| F · Week strip | Nothing; swaps N segments for seven weekdays | None | Small |

**A** and **E** are the two worth building. A is pure subtraction from what ships and carries no
risk. E is the one that actually looks minimal — but one card-wide gesture then has to serve
check-in, undo and opening the pact, and photo check-ins complicate it.

**C** and **D** are not card redesigns, they are Home redesigns: both delete the swipe deck, which
is the real reason a pact you own can be invisible on Home today. Worth a separate decision.

**F** needs no backend work either. `CrewWeek.checkIns` is every check-in in the week, each
carrying `pactId`, `userId` and `day`, so *which* days were kept is already on the card —
`week.days()` just happens to fold it to a total. The only real cost is that F is the busiest of
the six: it buys the better fact by spending the minimalism.

See `right-zone.html` for a focused pass on the empty box to the right of the count.

Everything renders on the real chassis: `pactPalette` tints, a 1px outline mixed `.28` to black,
the solid 3px bottom edge at `.24`, an 18px corner, Rubik in 400/500/600/700 only, and cards at a
true 336px so the proportions are honest.
