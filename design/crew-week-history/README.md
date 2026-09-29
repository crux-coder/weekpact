# Crew week — history

Four ways to scroll back through past weeks on the crew week page. Open `index.html`.

The page today (`lib/src/crew/crew_week_page.dart`) is one viewport: crew name, "This week ·
dates", the progress + streak pair, the pact carousel, dots, and the stone "checked in today"
panel. It only ever loads the current week (`fetchWeek(crewId)`). Each option adds one control
and leaves everything else where it is. In all four a past week is read-only: no today marker on
the calendar, no check-in, and the stone panel reads "All 4 hit their target · Week of Sep 14".

| Option | Control | Adds | Cost |
| --- | --- | --- | --- |
| A · Week stepper | ‹ › on the subtitle line | Nothing else | Small: `fetchWeek(crewId, weekStart:)` |
| B · Week strip | Row of week chips with % under the title | Summary view/query per week | Medium; costs ~70pt of card height |
| C · Stack below | "Past weeks" rows under the stone panel, page scrolls | Summary query + detail page | Large: drops the one-viewport FittedBox |
| D · Pull card down | Vertical drag on the pact card | Nested PageView | Medium; collides with pull-to-refresh |

**A** is the pick: the smallest change, and it is where the eye already goes to find out which
week it is looking at. It needs one backend change (a week-start parameter on `fetchWeek`, the
streak and percent already come with the week row). If history needs to be *seen* rather than
*reached*, add **C**'s rows underneath later; A remains the detail view.

**D** is the nicest gesture but must never ship alone — a hidden vertical drag on a card that
already swipes sideways is not discoverable, and the page's pull-to-refresh already owns that
direction.

## What shipped

**C** for the list, and **D** from `past-week.html` for the detail.
`lib/src/crew/crew_week_page.dart` keeps this week as one viewport and gives up the
height of one heading under it, so "Past weeks" shows under the fold and says the page
goes on. Under it, one `_PastWeekRow` per finished week: the dates, seven segments (the
share of the crew out each day, the calendar's kept green, firmer the more of the crew it
was), the crew's percentage in `doneMark` when it reached 100. Twelve weeks come at a time,
and a full page offers `EARLIER WEEKS`. A crew still in its first week has no list and stays
one viewport.

Tapping a row opens `showPastWeekSheet` (`lib/src/crew/past_week_sheet.dart`): a sheet on
the charcoal canvas that rises over the live page, which stays dimmed behind it. The sheet
leads with the date under a "LAST WEEK" or "PAST WEEK" chip, does not repeat the crew's
name, and replaces the progress + streak pair with one "Week closed" banner (percentage,
who hit their target, a lock). The pact deck is the same `CrewPactCarousel`
(`lib/src/crew/crew_pact_carousel.dart`) the page draws, now shared. The sheet asks the
backend for that week (`fetchWeek(crewId, weekStart:)`, the `crew_week_snapshot(uuid, date)`
overload in `supabase/migrations/20260929120000_add_crew_week_history.sql`), which comes
back with the real `today`, so the calendar carries no today marker and no future days and
the card says "that week". The list itself is `crew_week_history`, measured the way the
streak is: against the crew's current pacts and members, each counted from the week it
arrived.

`test/crew_week_history_test.dart` covers it, and renders the states to `/tmp` when run
with `--dart-define=CAPTURE_DESIGN=true`.

## Telling a past week apart

Open `past-week.html`. What shipped makes a past week look like the live one. Five ways to
make it read as the past: **A** the date becomes the title with a "PAST WEEK" chip and the
crew name demoted; **B** the progress + streak pair becomes one "Week closed" banner with a
lock and no "today" panel; **C** archive grey card tone; **D** the past week rises as a sheet
over the live page; **E** week tabs under the name with "THIS WEEK" in the streak's orange.
**A + B together** is the recommendation: no new colour language, no new gesture.
