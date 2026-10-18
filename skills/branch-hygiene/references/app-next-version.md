---
type: reference
---

# Apps: Advance `development` to the Next Marketing Version

After the sync step, `development` carries the same `MARKETING_VERSION` as `main` — the version that just shipped. The ship-app doctrine (`DEVELOPMENT_PATTERN.md`, invariant 4) says `development` always carries the **next** version and `main` the **current shipping** one, so `development` has to move now. This is the app equivalent of the library `-dev` stamp, with one hard difference:

**Apps never get a `-dev` suffix.** `MARKETING_VERSION` must be clean numeric (`1.2.1`), or Xcode Cloud archives fail validation and App Store Connect rejects the build. The "this is a dev snapshot" signal for an app is simply that `development`'s version is ahead of `main`'s.

## Which bump

`--next patch` is the default because it is always safe: a patch bump can be re-bumped to minor or major at any point in the cycle by editing the xcconfig on `development` — the version only becomes real at the `development → main` merge. Pass `--next minor`, `--next major`, or an explicit `--next 2.0.0` when the next release's shape is already known.

## Per-app, from `.asc.json`

Every app in `apps[]` is versioned independently. Loop them; never assume one version file:

```bash
git checkout development && git pull origin development

bump() {  # bump <version> <patch|minor|major|X.Y.Z>
  local v="$1" kind="$2" maj min pat
  IFS=. read -r maj min pat <<< "$v"
  case "$kind" in
    patch) echo "${maj}.${min}.$((pat + 1))" ;;
    minor) echo "${maj}.$((min + 1)).0" ;;
    major) echo "$((maj + 1)).0.0" ;;
    [0-9]*.[0-9]*.[0-9]*) echo "$kind" ;;
    *) echo "ABORT: bad --next '$kind'" >&2; return 1 ;;
  esac
}

jq -c '(.apps // [{name:(.app//.appId), xcconfig:.xcconfig, infoPlist:.infoPlist}])[]' .asc.json \
| while IFS= read -r app; do
    NAME=$(jq -r '.name' <<<"$app")
    XCCONFIG=$(jq -r '.xcconfig // empty' <<<"$app")
    PLIST=$(jq -r '.infoPlist // empty' <<<"$app")

    if [ -n "$XCCONFIG" ]; then
      CUR=$(grep -E '^\s*MARKETING_VERSION' "$XCCONFIG" | sed -E 's/.*=\s*//' | tr -d ' ')
      NEXT=$(bump "$CUR" "$NEXT_BUMP") || exit 1
      sed -i '' -E "s/^(\s*MARKETING_VERSION\s*=\s*).*/\1${NEXT}/" "$XCCONFIG"
    elif [ -n "$PLIST" ]; then
      CUR=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
      NEXT=$(bump "$CUR" "$NEXT_BUMP") || exit 1
      /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEXT}" "$PLIST"
    else
      # Single-app repo with neither: agvtool edits every target's plist.
      CUR=$(agvtool what-marketing-version -terse1)
      NEXT=$(bump "$CUR" "$NEXT_BUMP") || exit 1
      agvtool new-marketing-version "$NEXT" >/dev/null
    fi
    echo "${NAME}: ${CUR} → ${NEXT}"
  done
```

### Guards

- **Monotonic per app.** `NEXT` must sort strictly above `CUR` (`sort -V`). An explicit `--next X.Y.Z` that is not greater than every app's current version is an abort.
- **Clean semver only.** Refuse any `NEXT` matching `-` (no `-dev`, no `-rc`, no `-beta`).
- **Divergent apps are fine.** Each app bumps from its own current version. Two apps at `1.2.0` and `1.1.0` become `1.2.1` and `1.1.1` with `--next patch`.

## Do NOT touch

- `CURRENT_PROJECT_VERSION` / `CFBundleVersion` — build numbers climb via Xcode Cloud auto-increment or a deliberate bump on `development`, never as a side effect of starting a cycle (doctrine invariant 5).
- Dependency floors in `Package.swift` or `Package.resolved` — those are other libraries' versions.
- `release/<version>` branches and `v<version>` / `<version>-rc<n>` tags — permanent history.

## Commit

One commit, on `development`:

```bash
git add -A
git diff --cached --stat
git commit -m "Start next development cycle after v${RELEASED}

Advance MARKETING_VERSION on development (--next ${NEXT_BUMP}) so
development leads main again. Build numbers unchanged."
```

Push it (or open the chore PR into `development` if the branch requires PRs — see SKILL.md Step 2).
