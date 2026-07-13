#!/bin/bash
# validate-ci.sh — Thin orchestrator. Runs checks/[0-9]*.sh in lex order
# and summarizes pass/fail/skip.
#
# Usage:
#   ./validate-ci.sh [--app <name>] [--verbose] [--only NN[,NN...]]
#
# Each check is a standalone script in ./checks/. To debug a single check,
# run it directly:
#   ./checks/12-xcc-merge-to-main-workflow.sh --app MyApp --verbose
#
# Exit codes:
#   0 — all checks passed (or only skipped)
#   1 — at least one check failed
#   2 — orchestrator misuse (bad args, no checks found)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"

APP_ARG=""
VERBOSE=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --app)
      APP_ARG="$2"
      shift 2
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --only)
      ONLY="$2"
      shift 2
      ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--app <name>] [--verbose] [--only NN[,NN...]]

Runs all CI validation checks for the ship-app workflow.

Each check lives in $CHECKS_DIR/NN-<name>.sh and is independently runnable.
Exit codes per check: 0 pass, 1 fail, 2 skip.

Options:
  --app <name>      App Store Connect app name / id / bundle id
                    (overrides ASC_APP_ID env and .asc.json)
  --verbose, -v     Pass --verbose to each check (dumps raw JSON, etc.)
  --only NN[,NN..]  Run only the listed checks (by leading number).
                    Example: --only 12,13 runs xcc workflow checks only.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# Color
if [ -t 1 ]; then
  C_PASS=$'\033[32m'
  C_FAIL=$'\033[31m'
  C_SKIP=$'\033[33m'
  C_OFF=$'\033[0m'
else
  C_PASS=''; C_FAIL=''; C_SKIP=''; C_OFF=''
fi

shopt -s nullglob
ALL_CHECKS=("$CHECKS_DIR"/[0-9]*.sh)
if [ "${#ALL_CHECKS[@]}" -eq 0 ]; then
  echo "no checks found in $CHECKS_DIR" >&2
  exit 2
fi

# Header: list the apps that will be validated (per-app checks loop these).
# Source _common.sh for resolve_apps; CHECK_APP narrows to one app when --app set.
if command -v jq >/dev/null 2>&1; then
  CHECK_APP="$APP_ARG"
  # shellcheck source=checks/_common.sh
  . "$CHECKS_DIR/_common.sh" 2>/dev/null || true
  if declare -f resolve_apps >/dev/null 2>&1; then
    _apps_json=$(resolve_apps 2>/dev/null || echo "[]")
    _apps_n=$(echo "$_apps_json" | jq 'length' 2>/dev/null || echo 0)
    if [ "${_apps_n:-0}" -gt 0 ]; then
      _apps_list=$(echo "$_apps_json" | jq -r '[.[] | (.name // .appId)] | join(", ")')
      echo "Validating ${_apps_n} app(s): ${_apps_list}"
    else
      echo "Validating: no app resolved yet (check 06 will report)"
    fi
  fi
fi

declare -a CHECKS_TO_RUN
if [ -n "$ONLY" ]; then
  IFS=',' read -ra PICK <<< "$ONLY"
  for n in "${PICK[@]}"; do
    n=$(echo "$n" | xargs)  # trim
    found=""
    for c in "${ALL_CHECKS[@]}"; do
      base=$(basename "$c")
      case "$base" in
        ${n}-*)
          found="$c"
          break
          ;;
      esac
    done
    if [ -n "$found" ]; then
      CHECKS_TO_RUN+=("$found")
    else
      echo "warning: no check matching '$n'" >&2
    fi
  done
  if [ "${#CHECKS_TO_RUN[@]}" -eq 0 ]; then
    echo "no matching checks for --only $ONLY" >&2
    exit 2
  fi
else
  CHECKS_TO_RUN=("${ALL_CHECKS[@]}")
fi

declare -a RESULTS
PASS=0
FAIL=0
SKIP=0

for check in "${CHECKS_TO_RUN[@]}"; do
  args=()
  [ -n "$APP_ARG" ] && args+=(--app "$APP_ARG")
  [ "$VERBOSE" -eq 1 ] && args+=(--verbose)

  # Capture stdout (which contains the final pass/fail/skip line) and discard
  # stderr noise unless --verbose, in which case let it through.
  # `${args[@]+"${args[@]}"}` survives empty array under set -u on bash 3.2.
  if [ "$VERBOSE" -eq 1 ]; then
    output=$("$check" ${args[@]+"${args[@]}"})
    ec=$?
  else
    output=$("$check" ${args[@]+"${args[@]}"} 2>/dev/null)
    ec=$?
  fi

  base=$(basename "$check" .sh)
  last_line=$(echo "$output" | tail -1)

  case "$ec" in
    0)
      RESULTS+=("${C_PASS}PASS${C_OFF}  $base  —  $last_line")
      PASS=$((PASS + 1))
      ;;
    1)
      RESULTS+=("${C_FAIL}FAIL${C_OFF}  $base  —  $last_line")
      FAIL=$((FAIL + 1))
      ;;
    2)
      RESULTS+=("${C_SKIP}SKIP${C_OFF}  $base  —  $last_line")
      SKIP=$((SKIP + 1))
      ;;
    *)
      RESULTS+=("${C_FAIL}ERR ${C_OFF}  $base  —  exited $ec  —  $last_line")
      FAIL=$((FAIL + 1))
      ;;
  esac
done

echo
echo "=== ship-app CI validation ==="
for r in "${RESULTS[@]}"; do
  echo "$r"
done
echo
echo "Summary: ${C_PASS}${PASS} pass${C_OFF}, ${C_FAIL}${FAIL} fail${C_OFF}, ${C_SKIP}${SKIP} skip${C_OFF}"

if [ "$FAIL" -gt 0 ]; then
  echo "→ Re-run a failing check directly to debug:"
  echo "    $CHECKS_DIR/<check-name>.sh --app <app> --verbose"
  exit 1
fi

if [ "$PASS" -eq 0 ] && [ "$SKIP" -gt 0 ]; then
  echo "→ All checks skipped. Likely missing tooling or app id."
  exit 1
fi

echo "→ CI is sane. Safe to proceed."
exit 0
