# Sourced by the release scripts: keeps each store release on a version newer
# than the one installed apps were last told about.
#
# The update prompt compares X.Y.Z only, so a release that keeps the version of
# the live one can never be offered to anyone. public.app_releases holds what
# was last marked live (pnpm mark-released), so a build at or below it is
# refused before any time is spent on it.

# True when X.Y.Z $1 is newer than X.Y.Z $2.
version_newer() {
  local IFS=.
  local -a a=($1) b=($2)
  local i
  for i in 0 1 2; do
    (( 10#${a[i]} > 10#${b[i]} )) && return 0
    (( 10#${a[i]} < 10#${b[i]} )) && return 1
  done
  return 1
}

# The latest_version marked live for store $1 in the linked project.
live_release_version() {
  command -v supabase >/dev/null || return 1
  command -v jq >/dev/null || return 1
  supabase db query --linked \
    "select latest_version from public.app_releases where platform = '$1'" 2>/dev/null |
    jq -er '.rows[0].latest_version // empty'
}

# Fails unless version $2 is newer than what store $1 has marked live.
require_new_version() {
  local platform="$1" version="$2" live
  live="$(live_release_version "$platform")" ||
    fail "Could not read the live $platform version from public.app_releases (supabase link, jq). Pass --skip-version-check to build anyway."
  version_newer "$version" "$live" ||
    fail "pubspec.yaml is $version, but $platform $live is already marked live, so installed apps would never be told about this release. Run pnpm bump-version first."
  printf 'Version %s is newer than live %s %s\n' "$version" "$platform" "$live"
}
