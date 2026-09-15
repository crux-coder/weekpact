# WeekPact visual system

The app uses solid-color raised cards, flat icons, condensed typography, compact spacing, and restrained pastel accents. Cards have a darker color-matched outline and a crisp 2px bottom edge (3px for the main Home pact card), without blurred shadows. Dark cards use a lighter grey outline and edge. Avoid background gradients and attached title tabs.

## Where to make changes

- `lib/src/theme/weekpact_theme.dart`: palettes, theme configuration, and `WeekPactMetrics` for corner radii, strokes, spacing, and control sizes. `BuildContext` getters supply semantic canvas, surface, ink, muted, and accent colors.
- `lib/src/widgets/app_components.dart`: `AppSurface`, `AppSectionCard`, `AppButton`, `AppTextField`, and `AppBottomNavigationBar`. Section cards integrate their title/selector and optional actions within the same unbroken fill, without a colored header strip.
- `lib/src/widgets/app_sheet.dart`: `showAppSheet` and `AppSheet` for keyboard-aware modal forms.
- `lib/src/widgets/page_frame.dart`: consistent scrolling, page headings, loading placeholders, and footer placement.
- `lib/src/home/home_surface.dart`: the home carousel's light accent-card variant of `AppSurface`. Its fixed dark foreground keeps contrast against pale pact and crew surfaces in both themes.

## Theme behavior

Light uses a cream canvas, off-white surfaces, dark text, and pastel highlights. Dark uses a near-black canvas with the SAME off-white, pale yellow, and pale green cards as Home. Card content is always dark; only canvas text and navigation invert. Do not introduce olive, brown, charcoal, coral, or pink card variants. Both use the same component structure, metrics, and navigation. Appearance continues to support Light, Dark, and Device in Account and persists through the existing preference store.

All `AppSurface`, `AppSectionCard`, and `AppSheet` content uses a `builder: (context) => ...` API. Build color-dependent content inside that callback: `AppSurfaceTheme` scopes it to the pale-card palette even on a dark canvas. Use `context.ink` for canvas and regular surface text, `context.muted` for secondary text, and `context.border` for outlines. Explicit pastel home surfaces use `homeInk`; do not place dark-theme foreground colors onto those pale cards. Use `AppSurface.resolveTone: false` only when the component also deliberately owns its foreground contrast.

Use continuous squircle corners on cards (40px curve radius for standard cards), 8px control radius, 1px outlines, 12px page insets, and 48px primary controls. Preserve scroll access for longer forms and large text. Respect reduced-motion settings for finite transitions.

## Verification

`flutter test` covers authentication, onboarding, pacts, crews, invitations, account/theme switching, carousel behavior, avatar caching, and responsive home layouts. `test/design_preview_test.dart` visits all main destinations in both themes. Run it with `--dart-define=CAPTURE_DESIGN=true` to save eight rendered previews under `/tmp/weekpact-{light,dark}-{home,pacts,crews,account}.png`.

## Pacts overview

`lib/src/pacts/pacts_overview.dart` owns the personal weekly progress summary and square management cards. `YourWeekCard` reads the current crew week and caps each pact’s completed days at its target. `PactSquareGrid` uses two columns when space and text size permit and one column otherwise, keeping cards square. Editing remains owner-only.

### Crews: people first

`CrewPeopleGrid` lays out square `CrewPersonCard` tiles and the owner-only
`CrewInviteTile` with 12px gaps. It switches to one column on narrow screens or
large text settings. The current member uses sage; other tiles alternate the
shared offwhite and yellow palette. Circular profile images reuse Home's cached
profile loader, with initials and email fallbacks when profile data is unavailable.
Pending invitations expand below the grid; incoming invitations live in the header
inbox. Membership confirmation and owner permissions remain in `CrewPage`.

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
flat otherwise; today’s letter and date are bold without an underline or heavier
border. Preserve these state cues.

Home’s compact crew header has two solid raised containers with labels inside:
crew selection on the left and a narrower streak summary on the right. Use
`CrewHeaderSurface` for their shared 2px edge, outline, and squircle corners.

Buttons use `WeekPactMetrics.buttonShape` for squircle faces, outlines, and
raised edges. Preserve the existing tap areas and flat icon glyphs.

Pact icons are decorative: use flat filled squircle containers, without outlines
or elevation. Show status circles only for today and past unchecked dates;
future dates stay muted without markers. The streak flame is muted at zero and
orange once the streak starts. Offset the Home pact stack 12px left while
preserving card widths and preview strips.

Today’s Check-ins uses a single heading with a checked-members/total-members
count on its right. Collapsed panels contain only avatars and names, with
status conveyed by grouping and sage/neutral fills. Preserve explicit status
semantics and tap-to-expand behavior; show a collapse control when expanded.
