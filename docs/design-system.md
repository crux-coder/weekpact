# WeekPact visual system

The app uses flat, outlined surfaces, condensed typography, compact spacing, and restrained green/yellow accents. Avoid shadows, gradients, attached title tabs, and screen-specific navigation styling.

## Where to make changes

- `lib/src/theme/weekpact_theme.dart`: palettes, theme configuration, and `WeekPactMetrics` for corner radii, strokes, spacing, and control sizes. `BuildContext` getters supply semantic canvas, surface, ink, muted, and accent colors.
- `lib/src/widgets/app_components.dart`: `AppSurface`, `AppSectionCard`, `AppButton`, `AppTextField`, and `AppBottomNavigationBar`. Section cards integrate their title/selector and optional actions within the same unbroken fill, without a colored header strip.
- `lib/src/widgets/app_sheet.dart`: `showAppSheet` and `AppSheet` for keyboard-aware modal forms.
- `lib/src/widgets/page_frame.dart`: consistent scrolling, page headings, loading placeholders, and footer placement.
- `lib/src/home/home_surface.dart`: the home carousel's light accent-card variant of `AppSurface`. Its fixed dark foreground keeps contrast against pale goal and crew surfaces in both themes.

## Theme behavior

Light uses a cream canvas, off-white surfaces, dark text, and pastel highlights. Dark uses a near-black canvas with the SAME off-white, pale yellow, and pale green cards as Home. Card content is always dark; only canvas text and navigation invert. Do not introduce olive, brown, charcoal, coral, or pink card variants. Both use the same component structure, metrics, and navigation. Appearance continues to support Light, Dark, and Device in Account and persists through the existing preference store.

All `AppSurface`, `AppSectionCard`, and `AppSheet` content uses a `builder: (context) => ...` API. Build color-dependent content inside that callback: `AppSurfaceTheme` scopes it to the pale-card palette even on a dark canvas. Use `context.ink` for canvas and regular surface text, `context.muted` for secondary text, and `context.border` for outlines. Explicit pastel home surfaces use `homeInk`; do not place dark-theme foreground colors onto those pale cards. Use `AppSurface.resolveTone: false` only when the component also deliberately owns its foreground contrast.

Use a 12px card radius, 8px control radius, 1px outlines, 12px page insets, and 48px primary controls. Preserve scroll access for longer forms and large text. Respect reduced-motion settings for finite transitions.

## Verification

`flutter test` covers authentication, onboarding, goals, crews, invitations, account/theme switching, carousel behavior, avatar caching, and responsive home layouts. `test/design_preview_test.dart` visits all main destinations in both themes. Run it with `--dart-define=CAPTURE_DESIGN=true` to save eight rendered previews under `/tmp/weekpact-{light,dark}-{home,goals,crews,account}.png`.

## Goals overview

`lib/src/goals/goals_overview.dart` owns the weekly rhythm summary and square management cards. `WeeklyRhythmCard` sums scheduled days per week (not completions). `GoalSquareGrid` uses two columns when space and text size permit and one column otherwise, keeping cards square. Editing remains owner-only.

### Crews: people first

`CrewPeopleGrid` lays out square `CrewPersonCard` tiles and the owner-only
`CrewInviteTile` with 12px gaps. It switches to one column on narrow screens or
large text settings. The current member uses sage; other tiles alternate the
shared offwhite and yellow palette. Circular profile images reuse Home's cached
profile loader, with initials and email fallbacks when profile data is unavailable.
Pending invitations expand below the grid; incoming invitations live in the header
inbox. Membership confirmation and owner permissions remain in `CrewPage`.

### Account: profile hub

`AccountPage` uses a sage profile card above square Appearance and Notifications
tiles, followed by one panel of account actions. `AccountPreferenceTile` keeps
spacing and hierarchy consistent; larger text or narrow screens use one column.
`AppearanceChoices` is a compact Light/Dark/Device selector. Existing actions retain
confirmation and error handling; notification setup details open when needed.
`ProfileEditor` owns the name-editing form and lifecycle in a bottom sheet.

### Login, registration, and onboarding

`WelcomeCard` supplies a shared pastel introduction with an optional small eyebrow,
large heading, and one short supporting sentence. Login uses sage; registration
and the onboarding introduction use yellow. Forms sit on separate offwhite
surfaces with 8px gaps between cards and compact spacing between fields.
Onboarding presents three short step cards, then a photo/name form inside its own
surface. Both entry flows use the app's black/cream canvas and shared controls.
