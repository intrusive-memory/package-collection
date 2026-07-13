#!/bin/bash
# Sourced by checks/*.sh. Provides logging helpers, exit-code constants,
# common argument parsing, and App Store Connect app-id resolution.
#
# Exit-code contract for individual checks:
#   0 — PASS (the thing being checked is wired correctly)
#   1 — FAIL (the thing is missing or broken; user must fix)
#   2 — SKIP (a precondition is missing, so this check can't render a verdict)
#
# A check should print exactly one human-readable line on stdout via
# pass/fail/skip — the orchestrator captures that line for its summary table.

EXIT_PASS=0
EXIT_FAIL=1
EXIT_SKIP=2

CHECK_VERBOSE="${CHECK_VERBOSE:-0}"
CHECK_APP="${CHECK_APP:-}"

# Color codes (suppressed when stdout isn't a TTY so the orchestrator's
# captured strings stay clean).
if [ -t 1 ]; then
  C_PASS=$'\033[32m'
  C_FAIL=$'\033[31m'
  C_SKIP=$'\033[33m'
  C_INFO=$'\033[36m'
  C_OFF=$'\033[0m'
else
  C_PASS=''
  C_FAIL=''
  C_SKIP=''
  C_INFO=''
  C_OFF=''
fi

info() {
  [ "$CHECK_VERBOSE" = "1" ] && echo "${C_INFO}·${C_OFF} $*" >&2
  return 0
}

pass() {
  echo "${C_PASS}PASS${C_OFF}: $*"
  exit "$EXIT_PASS"
}

fail() {
  echo "${C_FAIL}FAIL${C_OFF}: $*"
  exit "$EXIT_FAIL"
}

skip() {
  echo "${C_SKIP}SKIP${C_OFF}: $*"
  exit "$EXIT_SKIP"
}

# Parse common flags. Sets CHECK_APP and CHECK_VERBOSE. Remaining args land
# in the REMAINING array for the caller to handle.
parse_common_args() {
  REMAINING=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --app)
        CHECK_APP="$2"
        shift 2
        ;;
      --verbose|-v)
        CHECK_VERBOSE=1
        shift
        ;;
      --)
        shift
        while [ $# -gt 0 ]; do
          REMAINING+=("$1")
          shift
        done
        ;;
      *)
        REMAINING+=("$1")
        shift
        ;;
    esac
  done
}

# Resolve the set of App Store Connect apps shipping from this repo.
#
# Echoes a JSON ARRAY of normalized app objects, each shaped:
#   { name, appId, bundleId, platform, scheme, xcconfig, infoPlist }
# (missing keys are null). One repo can ship several apps (e.g. an iOS app and
# a macOS app, each its own ASC record/scheme) — every per-app check loops this.
#
# Source order:
#   1. .asc.json `apps` array (the canonical multi-app declaration), OR
#   2. a single app synthesized from (in order) --app / $ASC_APP_ID /
#      .asc.json `.app|.appId` — so legacy single-app repos keep working.
#
# When --app (CHECK_APP) is set AND .asc.json declares apps[], the result is
# NARROWED to the one app whose name/appId/bundleId/scheme matches CHECK_APP.
#
# Always echoes valid JSON (`[]` if nothing resolvable). Never exits.
resolve_apps() {
  command -v jq >/dev/null || { echo "[]"; return 0; }

  local arr=""
  if [ -f .asc.json ]; then
    arr=$(jq -c '
      (.apps // []) | map({
        name:     (.name // .app // .appId // null),
        appId:    (.appId // .id // null),
        bundleId: (.bundleId // .bundleID // null),
        platform: (.platform // null),
        scheme:   (.scheme // null),
        xcconfig: (.xcconfig // null),
        infoPlist:(.infoPlist // .infoplist // null)
      })' .asc.json 2>/dev/null)
  fi

  # If .asc.json declared a non-empty apps[], use it (optionally narrowed).
  if [ -n "$arr" ] && [ "$(echo "$arr" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
    if [ -n "$CHECK_APP" ]; then
      local narrowed
      narrowed=$(echo "$arr" | jq -c --arg q "$CHECK_APP" \
        'map(select(.name==$q or .appId==$q or .bundleId==$q or .scheme==$q))')
      if [ "$(echo "$narrowed" | jq 'length')" -gt 0 ]; then
        echo "$narrowed"
        return 0
      fi
      # No match by field — fall through to a synthesized single app from --app.
    else
      echo "$arr"
      return 0
    fi
  fi

  # Synthesize a single app from --app / ASC_APP_ID / .asc.json .app|.appId.
  local id=""
  if [ -n "$CHECK_APP" ]; then
    id="$CHECK_APP"
  elif [ -n "${ASC_APP_ID:-}" ]; then
    id="$ASC_APP_ID"
  elif [ -f .asc.json ]; then
    id=$(jq -r '.app // .appId // empty' .asc.json 2>/dev/null)
  fi

  if [ -n "$id" ] && [ "$id" != "null" ]; then
    jq -nc --arg id "$id" \
      '[{name:$id, appId:$id, bundleId:null, platform:null, scheme:null, xcconfig:null, infoPlist:null}]'
    return 0
  fi

  echo "[]"
}

# Resolve a SINGLE App Store Connect app identifier (the first app's id).
# Retained for the non-app-looping checks (01–08) and as a convenience.
#
# Source order:
#   1. --app argument (parsed into CHECK_APP)
#   2. $ASC_APP_ID environment variable
#   3. .asc.json at repo root (`apps[0].appId`, then `.app` / `.appId`)
#
# Echoes the identifier, or empty string if unresolvable. Never exits.
resolve_app_id() {
  if [ -n "$CHECK_APP" ]; then
    echo "$CHECK_APP"
    return 0
  fi
  if [ -n "${ASC_APP_ID:-}" ]; then
    echo "$ASC_APP_ID"
    return 0
  fi
  if [ -f .asc.json ] && command -v jq >/dev/null; then
    local val
    val=$(jq -r '(.apps // [])[0].appId // (.apps // [])[0].id // .app // .appId // empty' .asc.json 2>/dev/null)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
      echo "$val"
      return 0
    fi
  fi
  echo ""
}

# Read one field from a single app JSON object (as echoed per-element by
# `resolve_apps | jq -c '.[]'`). Treats JSON null / missing as empty string.
#   app_field "$app_json" appId
app_field() {
  echo "$1" | jq -r --arg k "$2" '.[$k] // empty' 2>/dev/null
}

# A short human label for an app object: its name, else appId, else "(app)".
app_label() {
  local n a
  n=$(app_field "$1" name)
  a=$(app_field "$1" appId)
  echo "${n:-${a:-(app)}}"
}

# Fetch + normalize the Xcode Cloud workflows for an app id into a JSON array.
# Echoes "[]" on any failure. Never exits.
xcc_workflows() {
  asc xcode-cloud workflows list --app "$1" --output json --paginate 2>/dev/null \
    | jq '.data // .' 2>/dev/null || echo "[]"
}

# Roll a per-app verdict (0 pass / 1 fail / 2 skip) into running counters.
# Maintains globals AGG_PASS / AGG_FAIL / AGG_SKIP. Call agg_reset first.
agg_reset() { AGG_PASS=0; AGG_FAIL=0; AGG_SKIP=0; }
agg_add() {
  case "$1" in
    0) AGG_PASS=$((AGG_PASS + 1)) ;;
    1) AGG_FAIL=$((AGG_FAIL + 1)) ;;
    *) AGG_SKIP=$((AGG_SKIP + 1)) ;;
  esac
}
# Emit the final pass/fail/skip for an aggregated per-app check.
#   agg_finish "<summary message>"
# PASS if ≥1 app passed and none failed; FAIL if any app failed;
# SKIP if every app skipped (nothing participated).
agg_finish() {
  if [ "${AGG_FAIL:-0}" -gt 0 ]; then
    fail "$1 (${AGG_PASS:-0} ok, ${AGG_FAIL} failed, ${AGG_SKIP:-0} skipped)"
  elif [ "${AGG_PASS:-0}" -gt 0 ]; then
    pass "$1 (${AGG_PASS} ok, ${AGG_SKIP:-0} skipped)"
  else
    skip "$1 (no participating apps; ${AGG_SKIP:-0} skipped)"
  fi
}
