#!/bin/bash
# distribute-testflight.sh — Phase A.7 of ship-app.
#
# Once a `main` build has landed in App Store Connect (processingState=VALID),
# attach it to the TestFlight group(s) that run QA and write its "What to Test"
# notes from the git history it carries. Loops every app in .asc.json apps[]
# (or the legacy single app). Every platform build with that build number
# (iOS + macOS from one scheme, say) gets the same notes.
#
# Note scoping — the load-bearing rule:
#   * A RE-ROLL of a version already carrying RC tags (1.2.0-rc2 exists and
#     this build will become 1.2.0-rc3) gets ONLY what is new since the previous
#     RC tag. Testers already saw the rest.
#   * The FIRST candidate of a new version (no <version>-rc* tag yet) gets
#     EVERYTHING since the last shipped release (the newest v<X.Y.Z> tag; falls
#     back to the newest RC tag of the previous version, then to the whole
#     history, capped).
#   Override with --kind rc|release or an explicit --since <ref>.
#
# Usage:
#   distribute-testflight.sh [--app <name|id>] [--commit <sha>] [--build-number <n>]
#                            [--kind auto|rc|release] [--since <ref>]
#                            [--group <name|id>[,...]] [--locale en-US]
#                            [--notes-file <path>] [--print-notes]
#                            [--dry-run] [--verbose]
#
# Defaults: --commit origin/main; build number resolved through the app's
# Xcode Cloud TestFlight (branch=main) workflow run for that commit; groups from
# .asc.json `.testflight.groups` (top-level or per app), else every internal
# group; locale from `.testflight.locale`, else en-US.
#
# .asc.json (optional):
#   { "testflight": { "groups": ["internal"], "locale": "en-US" } }
#
# Exit codes: 0 all apps done, 1 any app failed, 2 bad arguments / preconditions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/checks/_common.sh"

COMMIT=""
BUILD_NUMBER=""
KIND="auto"
SINCE=""
GROUPS_ARG=""
LOCALE=""
NOTES_FILE=""
PRINT_NOTES=0
DRY_RUN=0
MAX_NOTES=4000   # App Store Connect whatsNew limit

usage() { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --commit)        COMMIT="$2"; shift 2 ;;
    --build-number)  BUILD_NUMBER="$2"; shift 2 ;;
    --kind)          KIND="$2"; shift 2 ;;
    --since)         SINCE="$2"; shift 2 ;;
    --group)         GROUPS_ARG="$2"; shift 2 ;;
    --locale)        LOCALE="$2"; shift 2 ;;
    --notes-file)    NOTES_FILE="$2"; shift 2 ;;
    --print-notes)   PRINT_NOTES=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --help|-h)       usage ;;
    *)               ARGS+=("$1"); shift ;;
  esac
done
parse_common_args "${ARGS[@]+"${ARGS[@]}"}"

case "$KIND" in auto|rc|release) ;; *) echo "ERROR: --kind must be auto|rc|release" >&2; exit 2 ;; esac

log()  { echo "$*"; }
vlog() { [ "$CHECK_VERBOSE" = "1" ] && echo "  · $*" >&2; return 0; }
die()  { echo "ERROR: $*" >&2; exit 2; }

for tool in git jq asc; do command -v "$tool" >/dev/null || die "$tool not on PATH"; done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

git fetch -q origin --tags 2>/dev/null || true
COMMIT=$(git rev-parse --verify "${COMMIT:-origin/main}^{commit}" 2>/dev/null) || die "cannot resolve commit '${COMMIT:-origin/main}'"
SHORT=$(git rev-parse --short "$COMMIT")

# ── Version on the commit ──────────────────────────────────────────────────────
# Reads MARKETING_VERSION from the app's xcconfig (or the repo's single
# Config/Version.xcconfig, any root xcconfig, then the pbxproj), at $COMMIT.
version_at_commit() {
  local app_xcconfig="$1" v="" f
  for f in "$app_xcconfig" Config/Version.xcconfig $(git ls-tree -r --name-only "$COMMIT" 2>/dev/null | grep -E '\.xcconfig$' | grep -v '/\.' ); do
    [ -z "$f" ] && continue
    # BSD sed/grep: use [[:space:]], never \s.
    v=$(git show "$COMMIT:$f" 2>/dev/null | grep -E '^[[:space:]]*MARKETING_VERSION[[:space:]]*=' | head -1 \
        | sed -E 's/.*=[[:space:]]*//; s/[[:space:]]*(\/\/.*)?$//' | tr -d '[:space:]')
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  f=$(git ls-tree -r --name-only "$COMMIT" | grep -E '\.xcodeproj/project\.pbxproj$' | head -1)
  [ -n "$f" ] && v=$(git show "$COMMIT:$f" 2>/dev/null | grep -E 'MARKETING_VERSION = ' | head -1 | sed -E 's/.*= *//; s/;.*//' | tr -d '[:space:]"')
  echo "$v"
}

# ── Build number from the Xcode Cloud TestFlight run for this commit ──────────
build_number_for_commit() {
  local appid="$1" wf runs run_id
  wf=$(xcc_workflows "$appid" | jq -r '.[] | select((.attributes.branchStartCondition // {}) | tostring | test("\"main\"";"i")) | .id' | head -1)
  [ -z "$wf" ] && return 1
  runs=$(asc xcode-cloud build-runs list --workflow-id "$wf" --limit 25 --sort "-number" --output json 2>/dev/null | jq '.data // []')
  run_id=$(echo "$runs" | jq -r --arg sha "$COMMIT" '.[] | select((.attributes.sourceCommit.commitSha // "") == $sha and (.attributes.executionProgress // "") == "COMPLETE") | .id' | head -1)
  [ -z "$run_id" ] && return 1
  asc xcode-cloud build-runs builds --run-id "$run_id" --output json 2>/dev/null | jq -r '(.data // [])[0].attributes.version // empty'
}

# ── Note scoping ───────────────────────────────────────────────────────────────
# Tags for this version that do NOT sit on $COMMIT (the current RC tag may
# already exist when this runs after Phase B).
prior_rc_tags() {
  local version="$1" t
  for t in $(git tag -l "${version}-rc*" | grep -E "^${version//./\\.}-rc[0-9]+$" | sort -V); do
    [ "$(git rev-parse "$t^{commit}")" = "$COMMIT" ] && continue
    git merge-base --is-ancestor "$t" "$COMMIT" 2>/dev/null && echo "$t"
  done
}
# Newest tag matching a regex that is an ancestor of $COMMIT (and not $COMMIT).
newest_ancestor_tag() {
  local re="$1" t
  for t in $(git tag -l | grep -E "$re" | sort -V -r); do
    [ "$(git rev-parse "$t^{commit}")" = "$COMMIT" ] && continue
    git merge-base --is-ancestor "$t" "$COMMIT" 2>/dev/null && { echo "$t"; return 0; }
  done
  return 1
}

decide_scope() {   # sets SCOPE_KIND and SCOPE_SINCE
  local version="$1" prior
  prior=$(prior_rc_tags "$version" | tail -1)
  SCOPE_KIND="$KIND"
  if [ "$SCOPE_KIND" = "auto" ]; then
    if [ -n "$prior" ]; then SCOPE_KIND="rc"; else SCOPE_KIND="release"; fi
  fi
  if [ -n "$SINCE" ]; then
    SCOPE_SINCE=$(git rev-parse --verify "$SINCE^{commit}" 2>/dev/null) || die "cannot resolve --since '$SINCE'"
    SCOPE_SINCE_LABEL="$SINCE"
    return
  fi
  if [ "$SCOPE_KIND" = "rc" ]; then
    [ -z "$prior" ] && die "--kind rc but no earlier ${version}-rc<n> tag precedes $SHORT; pass --since"
    SCOPE_SINCE="$prior"; SCOPE_SINCE_LABEL="$prior"; return
  fi
  # release: everything since the last shipped release
  SCOPE_SINCE=$(newest_ancestor_tag '^v[0-9]+\.[0-9]+\.[0-9]+$') \
    || SCOPE_SINCE=$(newest_ancestor_tag '^([0-9]+\.[0-9]+\.[0-9]+-rc[0-9]+|v[0-9]+(\.[0-9]+){1,2}-rc\.[0-9]+)$') \
    || SCOPE_SINCE=""
  SCOPE_SINCE_LABEL="${SCOPE_SINCE:-the beginning of history}"
}

# ── Notes text ─────────────────────────────────────────────────────────────────
# Conventional-commit subjects → three tester-facing sections. Internal-only
# kinds (test/docs/ci/style/test-cleanup/wip) and merge commits are dropped;
# chore/build/refactor/perf land under "Changed"; PR numbers are stripped.
compose_notes() {   # $1 app label, $2 version, $3 build number
  local label="$1" version="$2" build="$3" range subjects new fixed changed head tail body
  local -a logargs=(--no-merges --pretty='%s')
  if [ -n "$SCOPE_SINCE" ]; then range="$SCOPE_SINCE..$COMMIT"; else range="$COMMIT"; logargs+=(-n 60); fi
  subjects=$(git log "${logargs[@]}" "$range" 2>/dev/null \
    | grep -v -E '^(Merge |Revert "Merge )' \
    | grep -v -i -E '^(test|tests|docs|doc|ci|style|test-cleanup|wip)(\([^)]*\))?!?:' \
    | grep -v -i -E '^(wip|in progress|xcode regroup)$')
  # chore:/build:/refactor:/perf: stay (under Changed): a dependency bump such as
  # "chore: SwiftEscribo 0.4.4, Writing Tools off" is exactly what a tester must know.
  strip_prefix() { sed -E 's/^[A-Za-z]+(\([^)]*\))?!?:[[:space:]]*//'; }
  new=$(echo "$subjects"     | grep -i -E '^feat(\([^)]*\))?!?:'          | strip_prefix)
  fixed=$(echo "$subjects"   | grep -i -E '^(fix|hotfix)(\([^)]*\))?!?:'  | strip_prefix)
  changed=$(echo "$subjects" | grep -v -i -E '^(feat|fix|hotfix)(\([^)]*\))?!?:' | strip_prefix)
  # BSD sed has no \U — capitalize with awk.
  bullets() { [ -z "$1" ] && return; echo "$1" | sed -E 's/ \(#[0-9]+\)$//' | awk 'NF{print "• " toupper(substr($0,1,1)) substr($0,2)}'; }

  if [ "$SCOPE_KIND" = "rc" ]; then
    head="$label $version (build $build) — release candidate re-roll"
    tail="Only what changed since $SCOPE_SINCE_LABEL is listed; everything else matches that build."
  else
    head="$label $version (build $build) — new release candidate"
    tail="Everything since $SCOPE_SINCE_LABEL is new; please exercise the whole app."
  fi
  body=""
  [ -n "$new" ]     && body+=$'\nNew\n'"$(bullets "$new")"$'\n'
  [ -n "$fixed" ]   && body+=$'\nFixed\n'"$(bullets "$fixed")"$'\n'
  [ -n "$changed" ] && body+=$'\nChanged\n'"$(bullets "$changed")"$'\n'
  [ -z "$body" ]    && body=$'\n(No user-facing changes recorded in this range — internal fixes only.)\n'
  printf '%s\n%s\n%s\n' "$head" "$body" "$tail" | awk 'BEGIN{b=0} /^$/{ if(b) next; b=1; print; next } { b=0; print }'
}

truncate_notes() {
  local text="$1"
  if [ "${#text}" -gt "$MAX_NOTES" ]; then
    text="${text:0:$((MAX_NOTES - 2))}…"
    text="${text%$'\n'*}"$'\n…'
  fi
  printf '%s' "$text"
}

# ── Groups ─────────────────────────────────────────────────────────────────────
GROUP_ALL="[]"   # the app's beta groups, loaded in the main loop (not in a $(...) subshell)
load_groups() { GROUP_ALL=$(asc testflight groups list --app "$1" --output json --paginate 2>/dev/null | jq -c '.data // []'); }
group_name() { echo "$GROUP_ALL" | jq -r --arg id "$1" '(.[] | select(.id == $id) | .attributes.name) // $id' | head -1; }

resolve_group_ids() {   # $1 appid, $2 app json → space-separated ids (uses GROUP_ALL)
  local appid="$1" app="$2" all wanted ids=() w id
  all="$GROUP_ALL"
  if [ -n "$GROUPS_ARG" ]; then
    wanted=$(echo "$GROUPS_ARG" | tr ',' '\n')
  else
    wanted=$(jq -r --argjson app "$app" '
      ($app.testflight.groups // .testflight.groups // []) | .[]' .asc.json 2>/dev/null)
  fi
  if [ -z "$wanted" ]; then
    echo "$all" | jq -r '.[] | select(.attributes.isInternalGroup == true) | .id' | tr '\n' ' '
    return
  fi
  while IFS= read -r w; do
    [ -z "$w" ] && continue
    id=$(echo "$all" | jq -r --arg w "$w" '.[] | select(.id == $w or (.attributes.name | ascii_downcase) == ($w | ascii_downcase)) | .id' | head -1)
    [ -z "$id" ] && { echo "WARN: no TestFlight group named '$w' for app $appid" >&2; continue; }
    ids+=("$id")
  done <<< "$wanted"
  echo "${ids[*]+"${ids[*]}"}"
}

# ── Main loop ──────────────────────────────────────────────────────────────────
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length')" = "0" ] && die "no app resolvable (.asc.json / --app / ASC_APP_ID)"

[ -z "$LOCALE" ] && LOCALE=$(jq -r '.testflight.locale // empty' .asc.json 2>/dev/null)
LOCALE="${LOCALE:-en-US}"

FAILED=0
while IFS= read -r app; do
  [ -z "$app" ] && continue
  label=$(app_label "$app"); appid=$(app_field "$app" appId)
  # Prefer the human app name from .asc.json for the note header.
  name=$(jq -r --argjson app "$app" '$app.name // .name // $app.appId // empty' .asc.json 2>/dev/null)
  if [ -z "$name" ] || [ "$name" = "null" ] || [ "$name" = "$appid" ]; then name=$(jq -r '.name // empty' .asc.json 2>/dev/null); fi
  name="${name:-$label}"
  app_full=$(jq -c --argjson app "$app" --arg id "$appid" '(.apps // []) | map(select(.appId == $id)) | .[0] // $app' .asc.json 2>/dev/null || echo "$app")

  log "── $name ($appid) · commit $SHORT ──"
  version=$(version_at_commit "$(app_field "$app" xcconfig)")
  [ -z "$version" ] && { echo "  ERROR: cannot read MARKETING_VERSION at $SHORT" >&2; FAILED=1; continue; }

  bn="$BUILD_NUMBER"
  if [ -z "$bn" ]; then
    bn=$(build_number_for_commit "$appid") || true
    [ -z "$bn" ] && { echo "  ERROR: no completed TestFlight run for $SHORT; pass --build-number" >&2; FAILED=1; continue; }
  fi
  log "  version $version · build $bn"

  decide_scope "$version"
  log "  scope: $SCOPE_KIND · since $SCOPE_SINCE_LABEL"

  if [ -n "$NOTES_FILE" ]; then
    notes=$(cat "$NOTES_FILE") || { echo "  ERROR: cannot read $NOTES_FILE" >&2; FAILED=1; continue; }
  else
    notes=$(compose_notes "$name" "$version" "$bn")
  fi
  notes=$(truncate_notes "$notes")
  if [ "$PRINT_NOTES" = "1" ] || [ "$DRY_RUN" = "1" ]; then
    echo "  ┌─ What to Test ($LOCALE, ${#notes} chars)"; echo "$notes" | sed 's/^/  │ /'; echo "  └─"
  fi

  builds=$(asc builds list --app "$appid" --build-number "$bn" --output json --paginate 2>/dev/null \
    | jq -c --arg v "$version" '.data // [] | map(select(.attributes.processingState == "VALID"))')
  count=$(echo "$builds" | jq 'length')
  [ "$count" = "0" ] && { echo "  ERROR: no VALID build $bn in App Store Connect yet (processing?)" >&2; FAILED=1; continue; }

  load_groups "$appid"
  gids=$(resolve_group_ids "$appid" "$app_full")
  [ -z "$gids" ] && echo "  WARN: no TestFlight groups resolved — notes only"

  # Platform per build id: the builds list has no platform attribute, so ask per platform once.
  plat_map=""
  for p in IOS MAC_OS TV_OS VISION_OS; do
    for id in $(asc builds list --app "$appid" --build-number "$bn" --platform "$p" --output json 2>/dev/null | jq -r '.data[]?.id'); do
      plat_map+="$id=$p"$'\n'
    done
  done

  while IFS= read -r b; do
    bid=$(echo "$b" | jq -r '.id')
    plat=$(echo "$plat_map" | grep "^$bid=" | cut -d= -f2); plat="${plat:-?}"
    log "  build $bid ($plat)"

    # What to Test: ASC pre-creates an empty localization, so update when present.
    loc_exists=$(asc builds test-notes list --build-id "$bid" --output json 2>/dev/null | jq -r --arg l "$LOCALE" '.data[]? | select(.attributes.locale == $l) | .id' | head -1)
    if [ "$DRY_RUN" = "1" ]; then
      log "    dry-run: would $( [ -n "$loc_exists" ] && echo update || echo create ) $LOCALE notes"
    else
      if [ -n "$loc_exists" ]; then
        asc builds test-notes update --build-id "$bid" --locale "$LOCALE" --whats-new "$notes" --output json >/dev/null 2>&1 \
          && log "    notes updated ($LOCALE)" || { echo "    ERROR: test-notes update failed" >&2; FAILED=1; }
      else
        asc builds test-notes create --build-id "$bid" --locale "$LOCALE" --whats-new "$notes" --output json >/dev/null 2>&1 \
          && log "    notes created ($LOCALE)" || { echo "    ERROR: test-notes create failed" >&2; FAILED=1; }
      fi
    fi

    # Groups: never --submit here; external beta review is a deliberate, separate act.
    for gid in $gids; do
      gname=$(group_name "$gid")
      if [ "$DRY_RUN" = "1" ]; then
        asc builds add-groups --build-id "$bid" --group "$gid" --dry-run --output json >/dev/null 2>&1 \
          && log "    dry-run: would add to group '$gname'" || log "    dry-run: add-groups preflight failed for '$gname'"
      else
        out=$(asc builds add-groups --build-id "$bid" --group "$gid" --output json 2>&1) \
          && log "    added to group '$gname'" \
          || { if echo "$out" | grep -qi 'already'; then log "    already in group '$gname'"; else echo "    ERROR: add-groups '$gname': $(echo "$out" | head -2)" >&2; FAILED=1; fi; }
      fi
    done
  done <<< "$(echo "$builds" | jq -c '.[]')"
done <<< "$(echo "$APPS" | jq -c '.[]')"

exit "$FAILED"
