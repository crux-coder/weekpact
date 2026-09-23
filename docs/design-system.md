# WeekPact visual system

The app uses solid-color raised cards, flat icons, Rubik type, compact spacing, and quiet warm card tints on a neutral canvas. Cards have a darker color-matched outline and a crisp 2px bottom edge (3px for the main Home pact card), without blurred shadows. Dark cards use a lighter grey outline and edge. Avoid background gradients and attached title tabs.

## Where to make changes

- `lib/src/theme/weekpact_theme.dart`: palettes, theme configuration, and `WeekPactMetrics` for corner radii, strokes, spacing, and control sizes. `BuildContext` getters supply semantic canvas, surface, ink, muted, and accent colors. `WeekPactType`
  names the face: Rubik, set as the theme's default and the whole of the app's
  type — display, body copy, captions and numerals alike.
  `WeekPactType.primary` is that family and `WeekPactType.secondary` (with
  `secondaryFallback`) is the same one under the caption's name, kept so the
  small-caps labels and numerals keep saying which role they are and a second
  face could return without rewriting them. Use these rather than writing the
  family strings at a call site. State colours are named too, so a screen
  never spells one as a hex literal: `mintEdge` and `pendingEdge` for the two
  crew tile states, `doneMark` for a completed check-in, `streak` for a running
  flame, `inkEdge` for the dark check-in button, `navSelected` for the selected
  nav tile, and `castShadow` where a shadow falls on the canvas with no card
  colour to mix from.
Four weights, and only four: **400** body, **500** label, **600** emphasis,
**700** display. Those are the weights `pubspec.yaml` ships, and
`type_policy_test.dart` fails the build on anything heavier in `lib/`. The app
used to ask for w800 and w900 everywhere, which cost nothing while the face was
RobotoCondensed — it shipped 400 and 700, so the heavy weights quietly rounded
down. Rubik ships them for real, and a page set in 900 shouts: the weight
stopped carrying hierarchy because everything had it. Size and colour separate
things here; weight is the last resort, not the first. A headline is 700 at 20pt
and over, 600 below it; a small-caps eyebrow or a caption is 500; body is 400.

- `lib/src/widgets/app_components.dart`: `AppSurface`, `AppSectionCard`, `AppButton`, `AppTextField`, and `AppBottomNavigationBar`.
- `lib/src/widgets/app_dialog.dart`: `AppDialog` and `AppDialogDismiss`. The app's own dialog, on the same raised squircle as every other surface. Its actions stack full width as real buttons rather than the cramped text links `AlertDialog` puts in a row, with the action being offered on top and the dismissal below it in `WeekPactColors.neutralInset`. Pass it to `showAppDialog`; prefer it over `AlertDialog` for anything the person is meant to choose between. Section cards integrate their title/selector and optional actions within the same unbroken fill, without a colored header strip.
- `lib/src/widgets/app_sheet.dart`: `showAppSheet` and `AppSheet` for keyboard-aware modal forms.
- `lib/src/widgets/page_frame.dart`: consistent scrolling, loading placeholders, and footer placement. `PageFrame.header` is optional, and
  most pages now pass nothing: there was a `PageHeading` here that opened each
  page with its own name and a full stop in that destination's tint, and it is
  gone. A page is reached by tapping its tab, which stays lit and labelled at
  the foot of the screen, so the title spent 48 points and the first thing the
  eye landed on telling people where they had just chosen to go.
  `CrewPageHeading` is what most of those pages put there instead: the crew's
  own name, centred on the page, with the page's controls laid over the row at
  the right. They are laid over rather than set beside it — the same way Home
  hangs its bell, and for the same reason — with the name padded clear of them
  at both ends, so a crew stays in the page's middle whether the page carries
  two controls, as Crews does, or none, as Pacts does.
- `lib/src/home/home_surface.dart`: the home carousel's light accent-card variant of `AppSurface`. Its fixed dark foreground keeps contrast against pale pact and crew surfaces on any tint.
- `lib/src/widgets/pact_icon_badge.dart`: `PactIconBadge`, the raised squircle
  carrying a pact's glyph in its badge colour. Its outline and edge are mixed
  from that one colour, so the badge stays one object across all ten.
- `tool/try_colors.py`: swaps colour constants, renders the main screens through
  the design-preview harness, and puts the theme file back. Use it to look at a
  palette before committing to one; it reports contrast against card ink.

## Theme behavior

The app has one theme. It is set at the root (`theme`/`themeMode` in `app.dart`)
and nothing changes it at runtime: a petrol charcoal canvas (`darkCanvas`,
#222A2B) with light canvas text and navigation, carrying pale marine cards. Card content is
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

`pactPalette` is the quay, not the water — clay, sage, blush, olive, straw,
rosewood, moss, apricot, mushroom, wheat. It is warm, and held low on purpose:
a card should read as tinted paper, not as a colour, and near-black card ink
clears 9:1 against every entry. Keep new tints in that band and in that family.
The list is ordered so neighbours sit far apart in hue — most crews run two or
three pacts, so the first few entries are the ones that have to look least
alike.

A card that quiet cannot also be what tells two pacts apart at a glance, so
`pactBadgePalette` does that: the same ten hues with the chroma the card gives
up, drawn as the pact's icon badge (`PactIconBadge`). The two lists are paired
by index — `pactTint(i)` and `pactBadge(i)` are one pact's card and its badge,
and a new tint needs a new badge on the same line, in the same hue.

`stone`, `coolGrey` and `mintGreen` are cooler and stay where they are: they
sit on the canvas and in panels rather than on a pact card. `keptDay` is the
warm green a kept day takes on the crew week's calendar — sea glass there read
as the one cool thing on a warm card. `sand` and `brass` carry a subscription
that is ending and a clap the viewer gave, so those read as themselves rather
than as one more card colour.

`salmon`, `lavender`, `lime`, `sky` and `lantern` are the five the palette
holds at full chroma, and the one place it is loud on purpose. Everything else
here is chosen to sit under ink; at the size of a small mark that reads as more
ink, which is why these five exist at all. They were the destinations' full
stops, one per page, until the page titles went; `salmon` still carries the
notification badge, and the rest are unspent — `lime` and `lantern` are
currently referenced nowhere. Each of the five stands clear of the canvas ink
and of the other four, and `theme_test.dart` holds that line in Lab rather than
in hex, so a new one cannot be waved through on the grounds that its number
looks different. Keep `lantern` clear of `streak` — that orange says a streak
is running and nothing else. `streak` and `crewProgress` are the two colours that answer to
nothing else in the palette — a running streak, and a crew week still being
kept. `crewProgress` is pale citron, the one hue the harbour does not carry, so
the card reads as a state rather than as another tint. `pendingCheckIns` stays plain grey with
none of the palette's blue-green in it: against a marine card set, waiting has
to read as absence of colour rather than as a paler sea.
There are exactly two card languages, and `WeekPactDarkCard` in
`weekpact_theme.dart` is the second one. Most of the app is a pale card with
dark ink. The content-heavy surfaces invert that — the story viewer, the paywall
and the subscription page — because the photos and the pricing carry the colour
there and a pale card would compete with them; Crew week's streak panel uses
the same fill. Take `fill`, `outline`, `ink` and
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
  stays proportional to the box instead of swallowing it. The crew switcher's
  open list, the invites pane, the navigation highlight, and the roster's
  `BandGlyph` squares.
- `buttonShape` — every button. A button that draws its own
  `RoundedRectangleBorder` is a bug.

`buttonShape` caps its corner at half the shortest side, which is why a small
square face takes `panelCurve` instead. A wide button never reaches that cap;
a 36pt square hits it at once and comes out on a continuous 18, and since a
continuous radius reads at roughly `cardCorner / cardCurve` of its number, the
square wore a corner of about 8 inside a 56pt band wearing 18. The cap is there
to stop corners overlapping on compact faces and is right for what it guards —
it is simply not the shape for a square that is all corner.

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
properties (`--canvas`, `--cream`, the ten `pactPalette` tints, the
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

`flutter test` covers authentication, onboarding, pacts, crews, invitations, account actions, carousel behavior, avatar caching, and responsive home layouts; `widget_test.dart` asserts the app keeps one theme and offers no appearance setting. `test/design_preview_test.dart` visits all main destinations against both palettes — the shipping charcoal one and the light one used for card scope — so a change is checked against both. Run it with `--dart-define=CAPTURE_DESIGN=true` to save the rendered previews under `/tmp/weekpact-{light,dark}-{home,pacts,crews,account}.png`.

## Pacts overview

`lib/src/pacts/pacts_overview.dart` owns the personal weekly progress summary and the management list. `YourWeekCard` reads the current crew week and caps each pact’s completed days at its target. `PactBarList` draws one full-width `PactBar` per pact, a track whose tinted fill spans the share of a seven day week the pact claims, so the list reads as one picture of the week. A pact's colours come from its position in the crew's pact list — `WeekPactColors.pactTint(index)` for the card and `pactBadge(index)` for its `PactIconBadge` — so Home's stack, the crew week carousel and this list all show the same pact the same way. Editing remains owner-only.

### Crews: people first

`CrewPeopleGrid` lays out square `CrewPersonCard` tiles and the owner-only
`CrewInviteTile` with 12px gaps. It switches to one column on narrow screens or
large text settings. The current member uses sage; other tiles alternate the
shared offwhite and yellow palette. Circular profile images reuse Home's cached
profile loader, with initials and email fallbacks when profile data is unavailable.
Pending invitations expand below the grid; incoming invitations live in the header
inbox. Membership confirmation and owner permissions remain in `CrewPage`.

### Feed: removed

There is no Feed destination. `lib/src/home/stories_rail.dart` carries today's
check-ins and the notification list behind Home's bell carries everything the
crew has told you, which between them is what the feed was for. The navigation
bar has four destinations: Home, Pacts, Crews, Account. `lime` is unspoken for
in the destination-dot group, kept for a fifth.

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

`CrewHeaderSurface` is the shared 2px edge, outline and squircle corner for
the solid raised containers a crew header is built from — the crew week page's
own header panels, the crew strip and the activity card.

Home carries neither pair. It opens with the crew's name — the `CrewSwitcher`
title every crew-scoped page leads with — with `NotificationsBell` in the top
right across from it, and the crew's day under both: `StoriesRail`, one
squircle a member.

The bell and the name share that row as a `Stack` rather than a `Row`: laid
side by side, the name would be pushed off the page's middle by half a bell,
and the title is centred on the page or it is not centred. `HomeHeader.action`
is the corner slot, and the row stands at `NotificationsBell.size` — the taller
of the two things in it, and a real tap target — with the name centred in
whatever is left. `TodaySkeleton` draws the same row, and draws the bell from
the first frame: the count answers to what the crew has told you rather than
to this week, so it neither waits for the crews nor moves when they land. For
the same reason the bell counts for itself instead of riding Home's refresh —
it should not be reread every time a pact is saved or a crew is switched.

`_hasSelector` on Home's destination is
simply whether the crews have arrived, and `_headerHeight` follows it: the
page's minimum height and the unfolding panels' `top` both read that rather
than `HomeHeader.height`, and `TodaySkeleton` draws the slot only when it is
handed a live control, so nothing is promised before the page knows which crew
it is about.

The page's own name and dot used to stand there and no longer does: the
navigation bar under the thumb already says which of the five destinations this
is. The crew streak went with it and has come back smaller, on the week card
below — see `_StreakMark`.

The rail is `MemberDay.read`'s order, and it is the whole crew every day: you
first, then whoever has a check-in you have not opened (newest first), then the
ones you have, then whoever is not in yet. A member who is in wears a ring in
the pact's own `pactBadge` colour, so the rail says what was kept before it is
opened; a member whose stories have all been seen wears the palette's plain
grey; a member with nothing kept wears a dashed outline of the same `AvatarShape`
the faces are cut to, at 55% — an empty seat rather than a quieter full one.
Names are first names, as the crew roster writes them, with the whole name in
the tooltip and in what a screen reader reads.

Nothing in the rail posts. A check-in is made on the pact card below, photo and
all, so there is no "+" on your own tile and no camera behind it — a tile only
opens what is already there, and a member who is not in takes no tap at all.
A tap opens `StoryViewer`: the crew's day full screen, walked with a tap on the
right and a tap on the left, out of one member's check-ins and into the next
one's. A check-in kept with a photo shows it, with the pact named in the shot's
bottom-left corner: the pact card in miniature, its tint carrying the pact's
own badge, cut to `WeekPactMetrics.buttonShape` like every compact face in the
app. A photo of a run and a photo of a book are both just a photo, and the
chip is what makes one a check-in. A check-in kept without a photo — most of
them, since most pacts ask for no photo — fills the same frame with a wash
instead: two soft lights over a dark fall, mixed from the pact's own tint and
badge, so a run and a reading night are different weather rather than
different layouts. It is a picture, not a card standing in for one — the page
is the same page whether or not the pact asked for a photo, and the chip in
the corner always sits on something. Where the lights fall comes from the
check-in's own id, through a seed that is stable across runs, since a story
that looked different each time it was opened would read as a picture that
changed. Neither says "kept": the page is a day's check-ins, so the only thing
left to date them is the hour, which sits under the name. The one thing the page asks of the reader is at its foot: a clap,
as a pill with the word on it rather than a tally you can tap, since a story is
one check-in filling the screen and can spare the width. It wears
`clapInk` only once given, as claps do everywhere, and it opens on the word
rather than a count — the week snapshot cannot read `check_in_claps`, so the
number appears when the write answers with one. There is no nudge beside it:
nudging is the roster's, where the cooldown that governs it is already read. Stories are today's and today's only, and which of them have been
seen is this device's business: `StorySeenStore` keeps the marks beside the
crew selection in preferences, under the day they belong to, so yesterday's
marks cannot leave today's rail looking read. Under the rail sits `CrewTodayBar`: the week drawn small on a
`CrewHeaderSurface`, at `HomeCrewPanel.cardHeight`. It takes its height from the
crew card rather than choosing one — the two are the same week read two ways,
by day and then by member, and a row shorter than the card beneath it read as
that card's caption instead of as its equal. Seven columns, Monday first off `CrewWeek.weekDays`,
each filled from the bottom to `CrewWeek.shareOut` — the share of the crew that
was out that day, a member counting once however many pacts they kept. A kept
day is a raised block standing in its trough, on the same crisp offset edge
every surface in the app stands on: `mintGreen` over a `mintEdge` outline and
edge on charcoal, `mintEdge` over `doneMark` on a pale surface, taking the
palette's own light-and-dark pair for a check-in rather than a stroke mixed for
it. The trough keeps `controlDepth` clear under the fill for that edge, so a day
kept by the whole crew fills the rest exactly and its edge lands on the trough's
floor — which is why a column's fill is measured against the track less its
depth. A day that has been and took nobody is the same box left empty, outlined
rather than filled, since a trough at the weight a column wants reads as a
column of something; a day still to come is a `DashedBorder`, so the week reads as
something being filled in rather than as days already missed. Today is the same
outline taken heavier — ink at `selectedBorder`, the weight the app marks a
selection with everywhere else — and its letter steps from `muted` to full ink
to match. It wore `salmon`, Home's own tint, and should not have: on a row where
some days are empty, a warm red reads as the alarm a warm red always reads as, a
day flagged rather than a day arrived at. Where you are standing is a position,
not a state, so it takes no hue of its own; colour in this row means kept, and
only kept. A single member of a large crew never falls below
four points, or one person would be drawn as nobody. At the right, past a hairline
rule, `Crew week` and the chevron: the columns are the count, and a figure beside
a picture of the same figure is the sentence this row replaced, set smaller. It
replaced a line of type — `userGroup`, `2 of 4 checked in today`, `Crew week ›` — which said the
one thing the rail above had already said and gave no sense of the week it
opened; that sentence is now only what a screen reader hears, since seven columns
read out as numbers would be a table nobody asked for. It is still the crew
week's door: `CrewWeekPage` lost its entrance when the week card put its chevron
down for a race track, and a page nothing opens is a page nobody has.
`CrewTodayBar.loading` is the same seven troughs with the label drawn as a bar,
and it carries no handle — there is nothing yet to open.

Under that the crew block is `HomeCrewPanel`, and it is a race rather than an
average — and, on a tap, a drawer. A raised squircle card headlines the week on one line — `THIS WEEK ·
5 DAYS LEFT` on the left, the viewer's place on the right where the percentage
used to be — and carries `_RaceTrack` under it: the whole crew on one lane,
each member at their own `CrewWeek.percent`, drawn by `CrewWeek.standings`.
The card keeps the crew week page's two states, `crewProgress` citron while
the week is being kept and sea glass once it is, and it stands at 80 rather
than 64, because a track is a row of faces and a face needs its own height.

A tap opens it. One track carrying the whole crew is least readable exactly
when a race is worth watching — a crew running close lands inside a few points
of each other, and `_RaceTrack.placements` answers that by nudging the faces
apart, which draws a race rather than reporting one. Opening the card swaps
that track for `_MemberLanes`: the same riders, `_RaceTrack.shownIn` picking
the same six, unstacked onto a rail each at the position the nudging had to
fudge, with the percentage at the end of the rail that a shared track has no
room for. The lanes run themselves in as the card opens: every face leaves the
start line and travels to its own share while its figure counts up beside it,
one lane after another down the order, on a small stagger — the crew leaves
together and arrives apart, which is the race. The card is not showing a new
fact when it opens, it is spreading a fact the track had piled up, and a field
that arrives already standing still reads as a second chart rather than as the
first one unstacked. `MediaQuery.disableAnimationsOf` puts the field straight
where it finished: the positions are the fact, the run is the flourish. The handle is `_OpenMark`, a chevron in the headline that turns over
— the card put a chevron down when it stopped being a way into the crew week,
and this one is a different job: it opens the card where it stands rather than
leaving the page, and it takes its width from the headline instead of from the
track, which is why the old one had to go. A crew of one gets no handle, since
there is no race to unstack. The open state is not remembered; the card exists
to answer "where is everyone" in a glance, and one that opens already open has
spent the glance. `HomeCrewPanel.height` stays the shut height and the open
card does not tell the page it grew: Home sizes its fixed composition off the
card at rest, so the drawer takes its room from the pact card's `Expanded`
share rather than from every measurement on the page at once.

`_Track` is what both states are laid out on — the crew's field and a single
member's `_SoloTrack` — so the two read as one object with a different thing
running on it, and the card does not change shape when a crew of one becomes a
crew of two. The lane is filled in behind the front runner in the bar's own
solid `_ink`, ending under the leading face rather than at a figure of its
own: the fill and the front runner are the same fact, so they end in the same
place. Early in a week that fill is short and mostly behind the faces
themselves, which is what a crew that has not started yet should look like.

`_FinishLine` closes the lane — `HugeIcons` `racingFlag` at the right edge,
with `_Track.laneWidth` stopping short of it so a member on a kept week stands
against the flag rather than under it. It arrived with the card's chevron
leaving: the card took the tap into the crew week while it was a headline and
a bar, and a race you can see the whole of is not a summary asking to be
expanded. Nothing on Home opens `CrewWeekPage` now. The width that handle
stood in is the lane's, and a rule that simply stops is a bar, which is what
this card was before.

`percentCrew` still exists and the card no longer leads with it. A percentage
of a four-person week is the one number about a crew nobody can act on: it
averages four people into a figure none of them can move alone, and a
completion bar is the visual language of a project tracker. A place can be
moved. Ties share a place and the next one is skipped, as places do — four
members all on nothing are four firsts, not a first, a second, a third and a
fourth decided by whatever order the roster arrived in — and a crew that is
level all the way down reads `LEVEL` rather than handing the viewer a rank
that means nothing. A crew of one has nobody to race and keeps the bar, under
`YOUR WEEK`.

Two rules hold the track. Faces are placed at their own share and then nudged
just far enough apart to clear one another (`_RaceTrack.placements`, a forward
pass then a reverse one off the right edge), so members who are level read as
a tight pile on one mark rather than as a field spread across the card. And
nobody is marked out as last: the palette has `pendingCheckIns` for waiting and
the track pointedly does not spend it, because a crew's one shared card is not
the place to put a ring round whoever is behind. The viewer is ringed in ink
instead of the card's fill, and drawn last so their face is never the one
buried. A crew past `_RaceTrack.maxFaces` keeps the leader, the viewer and the
places around the viewer — a track cannot end in a `+3` the way a row of faces
can, because a count has no position.

A running crew streak sits beside the place as `_StreakMark`: `HugeIcons`
`fire` and the week count in `WeekPactColors.streak`, and nothing at all while
`streakWeeks` is zero. It is the palette's one loud colour and this is the one
place on Home that spends it.

The loading card stands the empty lane and its flag in place, so the line
above them does not move once the week arrives.

`CrewTodayStrip` (`lib/src/home/crew_today_strip.dart`) held the day under
that card — a line, a grip, and the crew's roster behind the pull. Home no
longer builds it, and `HomeCrewPanel` is the card alone: the score it led with
and the seats beside it both said who is in today, which the stories rail says
in faces, and once those went the pull was a handle on an empty row. A frame
around the single card that was left is a box drawn round one object, so the
frame went with it, and the card stands on the canvas.

The strip and `CrewMemberList` are here and unedited, as `CrewNamePlate`,
`CrewWeekButton` and `TodayCrewCard` are, and the strip's own tests host it
directly. The roster behind the strip's pull is still where every nudge can be
sent from — and Home now has its own door to one, because Home does not draw
that strip and the feature therefore had no entrance on the page people
actually open. A long press on a rail tile that is dashed opens `showNudge`
(`lib/src/home/nudge_sheet.dart`): an `AppDialog` naming the member, why they
are being nudged, and the one-per-24-hours rule.

Only a dashed tile takes the press, and never the viewer's own. A member who
is in has a story, so the tap is already spoken for; a member who is not is
the tile the thought is about. The tile carries no nudge mark and should not —
a rail of dashed squares each wearing a button would read as a page about who
is behind — so `onLongPressHint` on the tile's `Semantics` is the only place
the gesture is announced. The reason line is read off the week already in
hand: `CrewWeek.checkIns` covers this week, which is as far back as the offer
needs to look and as far as it can see without another call, and `nudgeReason`
turns it into plain days. `CrewNudgeState` is fetched with the week rather
than on the press, so the offer opens with its button in the state it is
really in; a states call that fails leaves the offer standing and asking the
server for itself, because the send is what actually knows whether a nudge is
allowed.

The countdown is a nudge, not a clock: it is the strip's own line rather than
a caption on something else, and it goes once the
whole crew is in — there is nothing left for the time to be left for. The
crew's day ends at midnight in the crew's timezone, and `crew_week_snapshot`
carries that day as a date rather than as a clock, so `CrewTodayStrip.timeLeft`
reads the device's own midnight and says nothing at all when the device's date
and the crew's have parted — a member abroad, or the minutes either side of a
rollover. A wrong countdown is worse than none. It refreshes on Home's
minute timer, with the rest of the week.

The whole roster is a pull away. The strip is a drawer front: a 96px pill that
slackens as the drawer comes out says so, and the pull — measured from where
the finger landed in global pixels — runs the drawer open under it pixel for
pixel. It commits past a quarter out or on a flick, hands back below that, and
a tap plays the pull straight through either way. It answers once, with a
medium impact when the drawer lands — not as it sets off. A buzz under a finger
that is still on its way answers a pull that can still be handed back, and
nothing has happened yet to feel. Do not put a chevron on it: this is the app's one pull, and the
grip is how it says so — a mark at the edge would say *tap*, which is what the
switcher above it does.

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
in` where it cannot. Because it mixes the two, every row wears which it is —
`checkedIn` gives the list the ids that are in, and each face carries the
strip's own seat at its corner: mint on a `mintEdge` with a tick for a day
that is kept, an empty one for a day still owed, in the dark face's border
rather than pale `pendingCheckIns`, since a pale dot repeated down a dark
column would shout louder than the tick it is meant to be quieter than. The
mark rides the face rather than taking a column: the row has already spent its
width on a name and a nudge.

Every row in the drawer carries that member's week under their name: a thin
`LinearProgressIndicator` in the surface's own ink on a let-down track of it,
with the share beside it as a percentage. It is `CrewWeek.percent`, which caps
each pact at the days it asked for, so nobody passes 100% by keeping a
three-day pact all seven — the crew progress card above reads the same way, so
a person's week and the crew's are one picture at two sizes. The bar fits
inside the height the face beside it already sets, so a row with a week on it
is no taller than one without, and the drawer's run — `_rowHeight` a member —
is unchanged. `CrewMemberList` takes the week; the panels that show one side
of the day leave it null and stay about today.

`head` is air over the first face and nothing more. A hairline hung there cut
the drawer in two rather than grouping what was under it, and the drawer's own
edge already says where the day's row ends. The caller sets the air, since a
drawer that runs exactly as far as its rows have to count it or clip the last
name. Escape, the back gesture, a tap outside and going inactive all shut it.

`HomeCrewPanel.loading` is the same card with its lines not yet filled in. The
block's height is fixed — `HomeCrewPanel.height`, which is the card's own — so
nothing moves when the week arrives, whatever the crew turns out to be. It
holds a fixed slice of a page that never scrolls, so larger system text is laid
out at the room it wants and scaled back into its slot rather than growing
one.

`CrewSwitcher` is the crew's name at the top of the page, centred, with
`arrowDown01` after it, and it is a page title first and a control second.
Every crew-scoped page leads with it — Home in `HomeHeader`'s `selector` slot
above the stories rail, Pacts and Crews through `CrewPageHeading.switcher`,
above their own heading — so the name of the crew you are reading about is in
the same place wherever you are, and switching is one gesture. `height` is 40
and `gap` is what a page leaves under it; the name sets at 22 in w600 and the
chevron is cut to match, and the two are centred as one object, so the name
alone sits slightly left of the page's middle. A tap opens a plain list: one
row a crew, the current one in w600 with a `tick02`, on `context.surface` at
`panelCurve`, anchored under the title by a `LayerLink` and dismissed by a tap
anywhere outside. The whole transition is a 140ms fade and a .96 scale from
the top, skipped under reduced motion.

A member of one crew gets the name with no chevron and no tap. The title still
earns its line — it says what the page is about — but a chevron on a list of
one is a promise the control cannot keep. Home's rule is only that the crews
have arrived; before that there is no title, because a page that does not yet
know its own subject should not guess at one.

What this replaced was much bigger: a 60pt raised card carrying a `YOUR CREW`
label over the name, which on a tap dealt every crew out as a tilted card in a
fanned hand (`CrewFan`, now deleted), each card loading that crew's week for
the faces and streak on it, over a scrim, with the control re-drawn above the
scrim so it would not go dark with the page, and a two-controller deal-and-exit
animation paced by the number of crews. That is a lot of machinery, and a lot
of waiting, for a choice between two or three names. `CrewPageSkeleton` no
longer stands a card in for it either — the control is in the header now, so a
placeholder in the body would promise something that lands somewhere else.

`CrewHeaderSurface` and `CrewControlLabel` stay in `crew_switcher.dart`: the
switcher no longer uses either, but the crew strip, the member list and the
crew page's panels all still do.
`CrewNamePlate`, `CrewWeekButton`, `TodayCrewCard` and `CrewCheckInTile` are
all still here and unedited, simply not built by Home. `RecentActivityCard` is
gone with the Feed it opened.
`ExpandableHomePanels` is still Home's host but has nothing to unfold
(`showCrewCheckIns` is false), so the check-in tiles are off the page for now.

The title rides the loading page rather than going down with it:
`TodaySkeleton` takes a `selector`, and Home hands it the live control as soon
as the crews are in, so choosing a crew neither blinks the title out nor moves
it while the new week loads. The control is dead while a check-in is saving —
a switch mid-write would save it against the crew being left.

Buttons use `WeekPactMetrics.buttonShape` for squircle faces, outlines, and
raised edges. Preserve the existing tap areas and flat icon glyphs.

`TodayPactsCard` gives the pact card everything its section is handed, less
its own heading and the row of dots: there is no ceiling on the card's height.
Home has no scrollbar to absorb a shortfall, so a fixed maximum there shows up
as dead floor under the stack.

The stack shows one card and a sliver. `TodayPactsCard.peekOf` is how much of
the next card shows past the front one — enough to say there is another card,
and no more — and the front card takes the rest of the width. The sliver
carries nothing: no icon, no score, no animation of its own. A card you cannot
act on has nothing to say, and a readout on a strip is read off the corner of
the card in front of it, which is where the eye is. A card's icon fades in and
out with the rest of its face, and the card sliding out parks right past the
edge of the box rather than leaving a second sliver on the left, which at this
width reads as an artefact of the page's padding. `TodaySkeleton` draws the
same shape: a wide card and an empty sliver.

Pact icons are decorative: render the glyph alone, without a background, outline,
or elevation. The Home pact stack carries no section label: the dots under it
say how many pacts there are and the card is unmistakably a pact, so
“YOUR PACTS” and the count beside it both went. Unchecked dates have no status circles; future dates remain readable at 65%
ink opacity. The streak flame is muted at zero and
orange once the streak starts. The Home pact stack is centred on the crew block
above it, front card and sliver together.

The strip above the crew tiles carries `LatestCheckInStrip` — the crew's freshest
check-in (“Mirnes checked in · Move for 30 min · 12m ago”) with the member's
avatar — rather than a section label. With nothing posted yet it reads “Nobody
has checked in yet today”. Omit the total fraction and standalone activity
card. Collapsed, a crew tile leads with the count at 34pt and a
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
