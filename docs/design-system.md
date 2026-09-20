# WeekPact visual system

The app uses solid-color raised cards, flat icons, condensed typography, compact spacing, and saturated mid-tone card tints on a neutral canvas. Cards have a darker color-matched outline and a crisp 2px bottom edge (3px for the main Home pact card), without blurred shadows. Dark cards use a lighter grey outline and edge. Avoid background gradients and attached title tabs.

## Where to make changes

- `lib/src/theme/weekpact_theme.dart`: palettes, theme configuration, and `WeekPactMetrics` for corner radii, strokes, spacing, and control sizes. `BuildContext` getters supply semantic canvas, surface, ink, muted, and accent colors. `WeekPactType`
  names the two faces: RobotoCondensed is the display face and the theme
  default, and `WeekPactType.secondary` (with `secondaryFallback`) is the wider
  companion for body copy, captions and numerals — use it rather than writing
  the family strings at a call site. State colours are named too, so a screen
  never spells one as a hex literal: `mintEdge` and `pendingEdge` for the two
  crew tile states, `doneMark` for a completed check-in, `streak` for a running
  flame, `inkEdge` for the dark check-in button, `navSelected` for the selected
  nav tile, and `castShadow` where a shadow falls on the canvas with no card
  colour to mix from.
- `lib/src/widgets/app_components.dart`: `AppSurface`, `AppSectionCard`, `AppButton`, `AppTextField`, and `AppBottomNavigationBar`.
- `lib/src/widgets/app_dialog.dart`: `AppDialog` and `AppDialogDismiss`. The app's own dialog, on the same raised squircle as every other surface. Its actions stack full width as real buttons rather than the cramped text links `AlertDialog` puts in a row, with the action being offered on top and the dismissal below it in `WeekPactColors.neutralInset`. Pass it to `showAppDialog`; prefer it over `AlertDialog` for anything the person is meant to choose between. Section cards integrate their title/selector and optional actions within the same unbroken fill, without a colored header strip.
- `lib/src/widgets/app_sheet.dart`: `showAppSheet` and `AppSheet` for keyboard-aware modal forms.
- `lib/src/widgets/page_frame.dart`: consistent scrolling, page headings, loading placeholders, and footer placement. `PageHeading`'s
  full stop is the destination's own tint, so a tab is recognisable before its
  title is read: Feed mint, Pacts butter, Crews sky, Account coral. Every
  destination passes its own `dotColor`; the default covers one-off pages
  outside the nav, such as an invitation.
- `lib/src/home/home_surface.dart`: the home carousel's light accent-card variant of `AppSurface`. Its fixed dark foreground keeps contrast against pale pact and crew surfaces on any tint.

## Theme behavior

The app has one theme. It is set at the root (`theme`/`themeMode` in `app.dart`)
and nothing changes it at runtime: a charcoal canvas (`darkCanvas`, #2B302C)
with light canvas text and navigation, carrying bright cards. Card content is
always dark, on every tint.

`WeekPactTheme.light` still exists, but it is not a second theme the app can be
put into. It is the pale-card scope: `AppSurfaceTheme` applies it inside card
builders so content on a cream or pact-tint fill resolves against a light
palette while the canvas around it stays charcoal. It is also what
`design_preview_test.dart` renders the light previews with. There is no
appearance setting — not in Account, not from the device, and no stored
preference; `widget_test.dart` asserts both. Changing the app's one theme means
editing the two root lines in `app.dart`, and the Android splash, iOS launch
screen and web chrome have to be changed to match by hand.

`pactPalette` carries bright colour — lemon, mint, sky, coral,
lavender, peach, lime, aqua, orchid, butter — held light enough that near-black
card ink clears 8.5:1 against every entry; keep new tints in that band. Its
companions follow the same family: `stone` is butter, `coolGrey` sky, `mintGreen`
mint, `softCoral` coral. `pendingCheckIns` stays muted grey, since reading as
*not done* is its job.
There are exactly two card languages, and `WeekPactDarkCard` in
`weekpact_theme.dart` is the second one. Most of the app is a pale card with
dark ink. Three content-heavy surfaces invert that — the Feed, the paywall and
the subscription page — because the photos and the pricing carry the colour
there and a pale card would compete with them; Crew week's streak panel and
Home's activity card use the same fill, and the activity card is built as that
panel is: a face where it puts its flame, a line in the card's own weight and a
muted caption under it. Take `fill`, `outline`, `ink` and
`muted` from `WeekPactDarkCard` together, as a closed set: never put pale-card
ink (`black`, `mutedLight`) on that fill, and never put dark-card ink on a pact
tint. Do not add a third card language, and do not introduce pink card variants.
Both use the same component structure, metrics, and navigation.

All `AppSurface`, `AppSectionCard`, and `AppSheet` content uses a `builder: (context) => ...` API. Build color-dependent content inside that callback: `AppSurfaceTheme` scopes it to the pale-card palette even on a dark canvas. Use `context.ink` for canvas and regular surface text, `context.muted` for secondary text, and `context.border` for outlines. Explicit pastel home surfaces use `homeInk`; do not place dark-theme foreground colors onto those pale cards. Use `AppSurface.resolveTone: false` only when the component also deliberately owns its foreground contrast.

There are four corners in `WeekPactMetrics`, and a screen should reach for one
of them rather than a new number:

- `controlRadius` (8) — a control, a cell or a flat panel, as a rounded rect.
  The crew week card's weekday cells and Home's activity pact chip are both
  this.
- `cardCorner` (18) / `cardCurve` (40) — a standard card, as a continuous
  squircle. They are the same corner: `cardCorner` is its plain radius and
  `cardCurve` is what that corner needs to read at the same size once drawn as
  a squircle. `curveFor` converts, so a surface can switch shape without a
  caller restating both. `pactCardShape` is `cardCurve` prebuilt.
- `panelCurve` (24) — a smaller raised panel, header or tile, so the curve
  stays proportional to the box instead of swallowing it. The crew switcher
  header, the crew fan cards, the invites pane and the navigation highlight.
- `buttonShape` — every button. A button that draws its own
  `RoundedRectangleBorder` is a bug.

Two more shapes sit outside the scale. `pill` is a bar, pip or progress track
rounded to its own half-height, so it reads as a pill at whatever size it is
rather than at a guessed radius — the Pacts progress bar, carousel dots, step
pips, sheet grab handles and skeleton bars are all this one value. Home's own
weekly segments are the exception: they are tall enough to carry a corner, so
they are cut to the squircle every cell is. Hold that corner to half the box it
cuts — a continuous corner that outgrows its box overshoots, and leaves stray
ticks of the border at the ends. `sheetRadius` (16) is a modal sheet, which meets the screen
edge and so rounds only along the top.

A dashed outline traces the same continuous squircle as the surface it sits on
(`DashedBorder`), so a dashed tile sits flush beside solid cards.

Also 1px outlines, 12px page insets, and 48px primary controls. Preserve scroll access for longer forms and large text. Respect reduced-motion settings for finite transitions.

## Transactional email

Two templates carry the system outside the app: `supabase/templates/confirmation.html`
(the auth confirmation, wired up in `supabase/config.toml`) and
`supabase/functions/invite-crew-member/template.ts` (the crew invitation). Both
are the same page: the charcoal canvas, the wordmark above it, and one cream
card holding everything else. Card ink is dark, captions are the same
uppercase letterspaced eyebrow the app uses, and the display face is
`'Roboto Condensed','Arial Narrow'` with Roboto for body copy. There is no
header strip and no attached title tab — the eyebrow sits inside the card's own
unbroken fill.

Colours are the app's, written as hex because email has no theme: cream
`#F5F6F5` card on `darkCanvas`, ink `#191B19`, muted `#51564F` on the card and
`#B8BEB5` on the canvas. Every raised box takes a 1px outline and a solid 2px
bottom edge (3px for the card) mixed from its own fill the way `AppSurface`
does — `Color.lerp(fill, black, .28)` for the outline and `.24` for the edge —
so mint `#8CDCAC` carries `#659E7C`/`#6AA783` and sky `#8AC9EC` carries
`#6391AA`/`#6999B3`. Corners are 18px for the card and 11px for panels,
buttons and the icon. No blurred shadows and no background gradients.

The primary action is mint on both, so the button reads the same wherever it
arrives. An accent panel is for content the reader has to take in — the crew
name on an invitation, in the Crews sky — not for repeating something they
already know.

Neither template loads an image, and neither should. Most clients block remote
images until the reader allows them, so an app icon in the header is absent on
first open for a large share of people — the wordmark is live HTML text, in the
display face with the destination's tint on its full stop, and reads the same
for everyone. Email also has no asset bundle, so any image means a hosted URL
and a deploy standing between a template change and a correct send. Keep the
brand mark as text.

## Website

`website/` is the third surface, and it carries the same system rather than a
look of its own. `src/styles/global.css` holds it: the app's colours as custom
properties (`--canvas` #2B302C, `--cream`, the ten `pactPalette` tints, the
charcoal card as `--dark-*`), the two faces (`WeekPact` is RobotoCondensed and
the default, `WeekPactText` is Roboto for body copy, captions and numerals),
and four corners matching `WeekPactMetrics`.

One recipe raises every box. A `.surface` is given its `--fill` and derives its
own outline and edge the way `AppSurface` does — `color-mix(in srgb, #000 28%,
var(--fill))` for the 1px outline and `24%` for the solid offset edge, which is
`Color.lerp(fill, black, .28)`/`.24` written for CSS. `.surface--card` steps
the edge to 3px, `.surface--dark` takes `WeekPactDarkCard`'s closed set, and
`.button`, `.nav-cta` and `.icon-tile` use the same derivation. There are no
blurred shadows and no background gradients. Corners are continuous squircles
through `corner-shape: squircle` where the browser draws them and plain rounded
rects everywhere else, so the shape degrades rather than breaking. The squircle
is the brand's corner, so every box takes it — cards, buttons, tiles, the
wordmark's icon, the screen switcher and the mock handset alike, not a chosen
few. The `@supports` block redefines the corner tokens rather than restating
radii per selector, so a box keeps asking for the corner it already asked for
(including the ones restated inside media queries) and lands on the app's own
curve: `--r-card` becomes `cardCurve` (40), `--r-panel` and `--r-button` become
`panelCurve` (24), matching `SquircleButtonBorder`'s cap. `--r-control` is
deliberately left out — a control, a cell or a flat panel is a rounded rect of
`controlRadius` on the web the same as it is in the app.

`src/components/HugeIcon.astro` carries the same Hugeicons Stroke Rounded 1.1.7
glyphs the app draws with, inlined as path data at build time so a page ships
only the marks it uses. A name on the site means the same mark it means in
`AppIcon`.

The wordmark's full stop is tinted per page, the way `PageHeading`'s is: the
layout takes a `tint` prop — mint on the landing page, sky on the invitation
and open-app handoffs, butter on Support, coral on Privacy and 404 — and every
`.dot` on the page reads it. The handoff pages are deliberately the same page as
the crew invitation email: charcoal canvas, wordmark above it, one cream card
holding everything else, sky icon panel and mint primary action. Changing one
means changing the other.

## Verification

`flutter test` covers authentication, onboarding, pacts, crews, invitations, account actions, carousel behavior, avatar caching, and responsive home layouts; `widget_test.dart` asserts the app keeps one theme and offers no appearance setting. `test/design_preview_test.dart` visits all main destinations against both palettes — the shipping charcoal one and the light one used for card scope — so a change is checked against both. Run it with `--dart-define=CAPTURE_DESIGN=true` to save the rendered previews under `/tmp/weekpact-{light,dark}-{home,feed,pacts,crews,account}.png`.

## Pacts overview

`lib/src/pacts/pacts_overview.dart` owns the personal weekly progress summary and square management cards. `YourWeekCard` reads the current crew week and caps each pact’s completed days at its target. `PactSquareGrid` uses two columns when space and text size permit and one column otherwise, keeping cards square. A pact's colour comes from `WeekPactColors.pactTint(index)` — its position in the crew's pact list — so Home's stack, the crew week carousel and this grid all show the same pact in the same colour. Editing remains owner-only.

### Crews: people first

`CrewPeopleGrid` lays out square `CrewPersonCard` tiles and the owner-only
`CrewInviteTile` with 12px gaps. It switches to one column on narrow screens or
large text settings. The current member uses sage; other tiles alternate the
shared offwhite and yellow palette. Circular profile images reuse Home's cached
profile loader, with initials and email fallbacks when profile data is unavailable.
Pending invitations expand below the grid; incoming invitations live in the header
inbox. Membership confirmation and owner permissions remain in `CrewPage`.

### Feed: check-ins from every crew

`lib/src/feed/feed_page.dart` is the second destination, between Home and Pacts.
It lists check-ins from every crew the member belongs to, newest first, one post
per check-in: a full-bleed 16:9 photo, then one text bar beneath it with the
author's avatar, the pact title leading, and the byline — name (“You” for your
own), crew and time — as muted secondary text beside a muted pact glyph. The
compact crop keeps a day's check-ins on one screen. Posts are deliberately quiet: one
`WeekPactDarkCard` surface, so the photo carries the colour.
The feed is the one place photos are not bowed by `CheckInPhotoFrame`; the card's
own corners clip them edge to edge. A check-in without a photo is the bar alone.
Day headings separate the stream, matching Home's date grouping. Paging
is keyed on the last entry, so new posts never shift a page; pull to refresh
reloads from the top. Photos and avatars arrive as signed URLs from
`HomeBackend.fetchFeed`, one batch per page, with an honest placeholder when an
image cannot be fetched.

### Account: profile hub

`AccountPage` uses the profile-first layout: a sand card with a centered avatar,
name, email, and pill-shaped Edit profile button. Notifications and optional crash
report sharing occupy two rows in one offwhite panel. Support and Privacy policy
are adjacent shortcut tiles, followed by a full-width Log out row and a separate,
subdued Delete account action. Reset password is omitted from Account; recovery
remains available through the sign-in flow. The page scrolls on smaller screens
and with larger text. Existing actions retain confirmation and error handling;
notification setup details open when needed. `ProfileEditor` owns the name-editing
form and lifecycle in a bottom sheet. `ProfileAvatar` supports a larger size and
initials while retaining the existing photo loader.

### Login, registration, and onboarding

`WelcomeCard` supplies a shared pastel introduction with an optional small eyebrow,
large heading, and one short supporting sentence. Login uses sage; registration
and the onboarding introduction use yellow. Forms sit on separate offwhite
surfaces with 8px gaps between cards and compact spacing between fields.
Onboarding presents three short step cards, then a photo/name form inside its own
surface. Both entry flows use the app's black/cream canvas and shared controls.

## Shared depth styling

`AppSurface` raises cards by default and uses continuous squircle corners. Its shadow is painted outside its clipped
Material face, preserving ink reactions, layout size, and rounded content. Set
`raised: false` for input fields or a surface whose caller already paints depth.
`HomeSurface` opts out of automatic depth to preserve Home’s custom treatments.

`AppIcon` renders a flat Hugeicons glyph with consistent spacing and inherits
`IconTheme` foreground colors. Icons, avatars, and uncompleted indicators have
no inset shading. Keep existing solid container fills and status colors.

Raised controls and supporting panels use crisp 2px offset edges; the main
Home pact card uses 3px. Both use solid edges and outlines only: no blurred
shadows. `RaisedIcon` opts individual icons into that treatment. The active
navigation card stays raised with a plain icon. The activity chevron retains
its opening press animation, which compresses the solid edge.

Home’s progress segments are raised on the check-in button's edge once the day
is kept, and flat before it. They sit close under that button: spare height in
the card gathers over the count instead, so the pair holds together whatever
height the card is standing in. Its pact card carries no weekday strip:
the week is read there as the count over the bar, with the days themselves left
to the crew week card. Its weekday cells are raised when complete and flat
otherwise; today’s letter and date are bold, with an outline reserved for
today. Completed days and the “Checked in today” banner use one cue that works on every tint: a cream fill (`_doneFill`), a green mark (`_doneMark`), and a raised edge mixed from the card's own colour. Do not tie an on-card completion cue to a fixed green — it fights the warm tints and vanishes on the green ones. Crew check-in tiles sit on the canvas, not a tint, and stay mint. Preserve these state cues.

Home’s compact crew header has two solid raised containers with labels inside:
crew selection on the left and a narrower streak summary on the right. Use
`CrewHeaderSurface` for their shared 2px edge, outline, and squircle corners.

Home carries neither. Its heading stands alone — the page's name and dot with
the crew streak beside it — and the crew block under it is `HomeCrewPanel`: a
recessed frame holding the week over the day. A raised squircle card headlines
it with the week — its icon, `CREW PROGRESS · THIS WEEK`, the percentage on the
same line and the bar under them — reading `CrewWeek.percentCrew`, which caps
each pact at its own weekly target, in the crew week page's own two states:
butter while the week is being kept, mint once it is. The label names its span
because the rows underneath cover a different one; a block holding both a week
and a day says which is which on each.

The card is also the way into the crew week, which is the same week at length,
so it takes the tap rather than a labelled row of its own: its inset sits
inside the `InkWell` so the whole face answers the finger, and a chevron at
`_chevronSize` stands at its right edge — sized as the card's own handle
rather than as a mark on it. The loading card keeps that width in reserve, so
the bar under it does not move once the week arrives, and offers no tap until
there is a week to open.

Under the card the block names today, and only today, in one line whatever
the crew's size — `CrewTodayStrip` in `lib/src/home/crew_today_strip.dart`. A
`TODAY` label, then the day as a score (`2/5 in today`) with today's check-ins
beside it as faces, hard right against the block's edge — so the day reads left
to right as a number and then the people behind it. The faces are the crew who
are in and only those: mint, lifted on a `mintEdge`, with a tick badge. Past
`maxFaces` the rest of them become one `+N`, and nobody who has yet to check in
appears at all — the score already counts them, and the drawer is where they
are read. A row per person would have grown the block with the crew and spent a
page that cannot scroll on people you are not waiting for.

The whole roster is a pull away. The strip is a drawer front: it wears the
same grip `CrewSwitcher` puts at the foot of its own card — the 96px pill that
slackens as the drawer comes out — and the same pull, measured from where the
finger landed in global pixels, running the drawer open under it pixel for
pixel. It commits past a quarter out or on a flick, hands back below that, and
a tap plays the pull straight through either way. It answers with the
switcher's own two beats: a light impact when the pull catches and the drawer
first comes out, a medium one when it lands. Do not put a chevron on it: the
grip is how this app says *pull*, and the two pulls should feel alike.

The drawer is the block carried further down, not a card laid over the page.
It keeps the block's face, comes out at the block's full width (`bleed`),
meets it flush with a square head and finishes on the block's own corner
(`curve`) with the lifted edge every raised surface here carries. Nothing
behind it is dimmed — the barrier catching the tap that shuts it paints
nothing. Inside, the front rides at the head and `CrewMemberList` slides out
underneath with `onDark: true`, which takes `WeekPactDarkCard`'s ink and
inverts the nudge button's face from `graphite` to `cream`, since graphite on
a dark panel is a shadow. The button is the app's raised button either way —
`AppSurface` on `buttonShape`, which mixes its own outline and lifted edge
from that face rather than spelling a second pair beside it. The drawer runs
exactly as far as the roster needs (`_rowHeight` per person plus the list's
foot), so it neither clips its last name nor opens onto empty floor. It holds the whole crew, not one side of it: `done:
false`, so the backend offers a nudge where one can be sent and says `Checked
in` where it cannot. Escape, the back gesture, a tap outside and leaving Home
all shut it.

`HomeCrewPanel.loading` is the same frame, card and day line with their lines
not yet filled in. The block's height is fixed — `HomeCrewPanel.height` — so
nothing moves when the week arrives, whatever the crew turns out to be. It
holds a fixed slice of a page that never scrolls, so larger system text is laid
out at the room it wants and scaled back into its slot rather than growing
one.

The crew switcher itself is unchanged and still opens from Pacts and Crews;
`CrewSwitcher`, `CrewNamePlate`, `CrewWeekButton`, `TodayCrewCard` and
`CrewCheckInTile` are all still here and unedited, simply not built by Home.
`ExpandableHomePanels` is still Home's host but has nothing to unfold
(`showCrewCheckIns` is false), so the check-in tiles and their nudges are off
the page for now.

Buttons use `WeekPactMetrics.buttonShape` for squircle faces, outlines, and
raised edges. Preserve the existing tap areas and flat icon glyphs.

`TodayPactsCard` gives the pact card everything its section is handed, less
its own heading and the row of dots: there is no ceiling on the card's height.
Home has no scrollbar to absorb a shortfall, so a fixed maximum there shows up
as dead floor under the stack.

Pact icons are decorative: render the glyph alone, without a background, outline,
or elevation. Label the Home pact section “YOUR PACTS” to reflect weekly progress. Unchecked dates have no status circles; future dates remain readable at 65%
ink opacity. The streak flame is muted at zero and
orange once the streak starts. Offset the Home pact stack 12px left while
preserving card widths and preview strips.

The strip above the crew tiles carries `LatestCheckInStrip` — the crew's freshest
check-in (“Mirnes checked in · Move for 30 min · 12m ago”) with the member's
avatar and a chevron into the Feed — rather than a section label. With nothing
posted yet it reads “Nobody has checked in yet today”. Omit the total fraction and
standalone activity card. Crew history no longer lives on Home; the Feed
destination carries it instead. Collapsed, a crew tile leads with the count at 34pt and a
lowercase caption under it (“checked in”, “not yet”), with faces to its right:
overlapping avatars with no rim, separated by the same raised edge the tile
carries, capped at three slots. The last slot becomes a “+n” chip when
the crew outgrows it, and a narrow tile drops to the chip alone — the expanded
list is where a big crew is read. Faces carry no names when collapsed, and the
count block scales down together rather than overflowing at large text sizes.
When one side is empty the tile speaks for the crew instead — its caption reads
“whole crew is in” or “be the first in today”. Expanded panels show the
“Checked in”/“Not yet” label with group counts, avatars, and names. Use sage for checked-in members and muted grey for pending
members. Preserve explicit status
semantics and tap-to-expand behavior; show a collapse control when expanded.

Check-in group labels use 10px medium-weight captions. Selected navigation
tiles use muted warm off-white (`navSelected`) rather than bright white.
