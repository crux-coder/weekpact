# WeekPact visual system

The app uses solid-color raised cards, flat icons, condensed typography, compact spacing, and saturated mid-tone card tints on a neutral canvas. Cards have a darker color-matched outline and a crisp 2px bottom edge (3px for the main Home pact card), without blurred shadows. Dark cards use a lighter grey outline and edge. Avoid background gradients and attached title tabs.

## Where to make changes

- `lib/src/theme/weekpact_theme.dart`: palettes, theme configuration, and `WeekPactMetrics` for corner radii, strokes, spacing, and control sizes. `BuildContext` getters supply semantic canvas, surface, ink, muted, and accent colors.
- `lib/src/widgets/app_components.dart`: `AppSurface`, `AppSectionCard`, `AppButton`, `AppTextField`, and `AppBottomNavigationBar`. Section cards integrate their title/selector and optional actions within the same unbroken fill, without a colored header strip.
- `lib/src/widgets/app_sheet.dart`: `showAppSheet` and `AppSheet` for keyboard-aware modal forms.
- `lib/src/widgets/page_frame.dart`: consistent scrolling, page headings, loading placeholders, and footer placement.
- `lib/src/home/home_surface.dart`: the home carousel's light accent-card variant of `AppSurface`. Its fixed dark foreground keeps contrast against pale pact and crew surfaces in both themes.

## Theme behavior

The app ships one theme, set at the root (`theme`/`themeMode` in `app.dart`); the
device's appearance setting does not change it, and the Android splash, iOS
launch screen and web chrome carry the same canvas colour. It is the dark one: a
charcoal canvas (`darkCanvas`, #2B302C) with light canvas text and navigation,
carrying the SAME bright cards as the light palette — card content stays dark on
every tint, including the cream feed posts. The light palette (`lightCanvas`,
#ECEDEA) stays defined and swaps in by changing those two root lines. Card content is always dark; only canvas text and
navigation invert. `pactPalette` carries bright colour — lemon, mint, sky, coral,
lavender, peach, lime, aqua, orchid, butter — held light enough that near-black
card ink clears 8.5:1 against every entry; keep new tints in that band. Its
companions follow the same family: `stone` is butter, `coolGrey` sky, `mintGreen`
mint, `softCoral` coral. `pendingCheckIns` stays muted grey, since reading as
*not done* is its job.
Do not introduce charcoal or pink card variants. Both use the same component structure, metrics, and navigation. Appearance continues to support Light, Dark, and Device in Account and persists through the existing preference store.

All `AppSurface`, `AppSectionCard`, and `AppSheet` content uses a `builder: (context) => ...` API. Build color-dependent content inside that callback: `AppSurfaceTheme` scopes it to the pale-card palette even on a dark canvas. Use `context.ink` for canvas and regular surface text, `context.muted` for secondary text, and `context.border` for outlines. Explicit pastel home surfaces use `homeInk`; do not place dark-theme foreground colors onto those pale cards. Use `AppSurface.resolveTone: false` only when the component also deliberately owns its foreground contrast.

Use continuous squircle corners on cards (40px curve radius for standard cards), 8px control radius, 1px outlines, 12px page insets, and 48px primary controls. Preserve scroll access for longer forms and large text. Respect reduced-motion settings for finite transitions.

## Verification

`flutter test` covers authentication, onboarding, pacts, crews, invitations, account/theme switching, carousel behavior, avatar caching, and responsive home layouts. `test/design_preview_test.dart` visits all main destinations in both themes. Run it with `--dart-define=CAPTURE_DESIGN=true` to save the rendered previews under `/tmp/weekpact-{light,dark}-{home,feed,pacts,crews,account}.png`.

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
compact crop keeps a day's check-ins on one screen. Posts are deliberately quiet:
one neutral `AppSurface` card in both themes, so the photo carries the colour.
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

Home’s progress bars remain flat. Weekday cells are raised when complete and
flat otherwise; today’s letter and date are bold, with an outline reserved for
today. Completed days and the “Checked in today” banner use one cue that works on every tint: a cream fill (`_doneFill`), a green mark (`_doneMark`), and a raised edge mixed from the card's own colour. Do not tie an on-card completion cue to a fixed green — it fights the warm tints and vanishes on the green ones. Crew check-in tiles sit on the canvas, not a tint, and stay mint. Preserve these state cues.

Home’s compact crew header has two solid raised containers with labels inside:
crew selection on the left and a narrower streak summary on the right. Use
`CrewHeaderSurface` for their shared 2px edge, outline, and squircle corners.

Buttons use `WeekPactMetrics.buttonShape` for squircle faces, outlines, and
raised edges. Preserve the existing tap areas and flat icon glyphs.

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
destination carries it instead. When one side is empty the single tile speaks for
the crew — “Whole crew is in”, “Be the first in today” — instead of showing a
count against nobody. Otherwise collapsed panels show small “Checked in”/“Not yet” labels with group counts,
avatars, and names. Use sage for checked-in members and muted grey for pending
members. Preserve explicit status
semantics and tap-to-expand behavior; show a collapse control when expanded.

Check-in group labels use 10px medium-weight captions. In dark mode, selected
navigation tiles use muted warm off-white rather than bright white.
