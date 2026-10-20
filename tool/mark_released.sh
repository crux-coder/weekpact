#!/usr/bin/env bash
# Tell installed apps a release is live: raise public.app_releases for a store.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
usage() {
  cat <<'HELP'
Usage: ./tool/mark_released.sh ios|android [--min [X.Y.Z]] [--message TEXT] [--local] [--dry-run]

Sets latest_version for the store to the version in pubspec.yaml, so older
builds offer the update once. Run it only after the release is live in the
store (approved and rolled out), never on upload: the prompt sends people to
the store, and a build they cannot download yet is a dead end.

  --min [X.Y.Z]   Also raise min_version, which blocks every older build until
                  it updates. Defaults to the pubspec version. Use it only when
                  a backend change breaks older builds.
  --message TEXT  Words for the prompt, such as what changed. Without it the
                  message is cleared and the app's default is shown.
  --local         Write to the local Supabase stack instead of the linked
                  project.
  --dry-run       Print the SQL without running it.
HELP
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

PLATFORM=""
MIN=""
MESSAGE=""
TARGET=--linked
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    ios|android) [[ -z "$PLATFORM" ]] || fail 'Name one store.'; PLATFORM="$1"; shift ;;
    --min)
      if [[ $# -ge 2 && "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then MIN="$2"; shift 2
      else MIN=pubspec; shift; fi ;;
    --message)
      [[ $# -ge 2 ]] || fail '--message requires a value'
      MESSAGE="$2"; shift 2 ;;
    --local) TARGET=--local; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) fail "Unknown option: $1 (use --help)" ;;
  esac
done
[[ -n "$PLATFORM" ]] || { usage >&2; exit 1; }

VERSION_LINE="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/p' pubspec.yaml)"
VERSION="${VERSION_LINE%%+*}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use version: X.Y.Z+N in pubspec.yaml.'
[[ "$MIN" != pubspec ]] || MIN="$VERSION"
(( ${#MESSAGE} <= 300 )) || fail 'Keep --message to 300 characters.'

# Single quotes doubled for SQL; the versions are already checked as X.Y.Z.
Q="'"
sql_text() { if [[ -z "$1" ]]; then printf 'null'; else printf "'%s'" "${1//$Q/$Q$Q}"; fi; }
SET="latest_version = '$VERSION', message = $(sql_text "$MESSAGE")"
[[ -z "$MIN" ]] || SET="$SET, min_version = '$MIN'"
# Versions compare as numbers, so a store can never be moved backwards, and
# min_version never passes latest_version.
SQL="$(cat <<SQL
with current as (
  select string_to_array(latest_version, '.')::int[] as latest
  from public.app_releases where platform = '$PLATFORM'
)
update public.app_releases set $SET
where platform = '$PLATFORM'
  and string_to_array('$VERSION', '.')::int[] >= (select latest from current)
  and string_to_array('${MIN:-0.0.0}', '.')::int[] <= string_to_array('$VERSION', '.')::int[]
returning platform, latest_version, min_version, message;
SQL
)"

if "$DRY_RUN"; then printf '%s\n' "$SQL"; exit 0; fi
command -v supabase >/dev/null || fail 'Install the Supabase CLI and run supabase link first.'
printf 'Marking WeekPact %s live on %s%s\n' "$VERSION" "$PLATFORM" "${MIN:+ (min $MIN)}"
OUTPUT="$(supabase db query "$TARGET" "$SQL")"
printf '%s\n' "$OUTPUT"
grep -q "$PLATFORM" <<<"$OUTPUT" || fail "Nothing changed: $VERSION is older than the live $PLATFORM release, or --min is above it."
