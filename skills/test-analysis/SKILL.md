---
name: test-analysis
description: Audit a Swift test suite across five dimensions and produce a single markdown findings report with concrete recommendations. Run multiple passes that each look at the test suite from a different angle — repetition, superfluity, coverage gaps (using real xccov data), flaky-in-CI risk, and CI gating of performance tests. Use this skill whenever the user asks to audit, analyze, review, critique, or clean up their tests, including phrases like "test analysis", "audit my tests", "review the test suite", "are there redundant tests", "find flaky tests", "test coverage gaps", "which tests can I delete", "are my tests good", or whenever they want a holistic read on Swift test-suite health. Triggers on Swift Package Manager / Xcode projects with XCTest or swift-testing test targets. Defer to Makefile targets when present; never run `swift test` or `swift build`.
---

# test-analysis

Audit a Swift test suite across five passes and compile findings into a single markdown report.

## Why this exists

Test suites accumulate cruft: copy-pasted assertions that drift out of sync, version-string tests that auto-pass forever, sleep-based "synchronization", expensive performance tests that creep into CI. Reading a test suite linearly to find these problems doesn't work — each defect type wants a different lens. This skill is those lenses, run one after another, with findings consolidated into one actionable report so the user can act on the whole picture rather than triaging in pieces.

## Inputs to gather first

Before starting any pass, establish:

1. **Repo root** and the **test target / scheme** (e.g., `MLXAudio-Package`). If multiple test targets exist, ask which to audit or do all of them.
2. **How tests are run**: prefer a Makefile target (`make test`) when present, otherwise `xcodebuild test -scheme <X> -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Never use `swift test` or `swift build`.
3. **CI workflow files** (`.github/workflows/*.yml`) — Pass 5 needs to know what actually runs in CI, which may differ from the default local target.
4. **Project-specific test categorization**: many Swift repos split tests into "CI-safe" vs. "local-only" (network, large model downloads, perf). Read `CLAUDE.md` / `AGENTS.md` / `README.md` for hints. If categories exist, respect them — flagging a network test as "flaky in CI" is wrong if the repo already excludes it from CI.

If anything is unclear, ask the user one focused question rather than guessing.

## Step 0 — Pre-flight `make lint`

Before any pass begins, run `make lint` from the repo root. This is the **only** action this skill is allowed to take that can affect the codebase — linters frequently auto-format or auto-fix on invocation, and that side effect is acceptable. Beyond `make lint`, the skill never edits, deletes, or rewrites code; the deliverable is a report and the user decides what to act on.

```bash
make lint
```

Three outcomes to handle:

1. **`make lint` succeeds** (exit 0, no diff or only formatting diff): proceed to the passes. If the lint pass produced a diff, mention it briefly in the eventual report's executive summary so the user knows the working tree changed.
2. **`make lint` fails** (exit non-zero, real lint errors): stop. Do not run any pass. Report the failure to the user with the first 30-50 lines of error output and ask whether they want to fix lint first or have you proceed anyway. Analysis on a codebase with lint errors gives muddled signal — coverage might be lower than it should be, flaky-prediction heuristics fire on transient violations, etc.
3. **`make lint` target doesn't exist** (or no Makefile): tell the user, name what you looked for (`make -n lint`), and ask whether to proceed without lint. Don't substitute another linter on your own — the user's project may have intentionally not wired one up.

This precondition matters because it ensures the suite under analysis is in the state the maintainers consider clean, not mid-edit. It also catches the common case where a user kicks off the analysis with uncommitted lint violations and gets a noisy report.

## The five passes

Each pass is independent. Run them in any order, but Pass 3 (coverage) is the slowest because it requires a full build+test, so kick it off early and let it run in the background while you do the static passes.

### Pass 1 — High-repetition tests

Two flavors, both worth flagging:

**Copy-paste assertion blocks.** Look for tests in the same file (or sibling files) that share an identical setup → call → assertion shape, varying only by input value. These are usually a sign that a parameterized helper or table-driven test would compress 10 tests into one. Heuristic: 3+ tests with structurally identical bodies and ≥80% line overlap modulo identifier renaming.

**High-iteration loops.** Look for `for _ in 0..<N` or `repeat...while` in test bodies where N is large (≥1000) and the body doesn't materially vary across iterations. These are usually fossilized stress tests that slow the suite without catching anything a smaller N wouldn't catch. Also flag tests that call the same generation/inference function many times with identical inputs expecting deterministic output — one call would do.

For each finding, record file path, line range, the pattern detected, and a one-line recommendation (refactor to a helper / reduce N to 10 / move to a perf-only target).

### Pass 2 — Superfluous tests

Tests that consume CI minutes without contributing signal. Common species:

- **Version / build-number assertions**: `XCTAssertEqual(MyLib.version, "1.2.3")`. Auto-passes after every bump and never catches anything useful.
- **Tautologies**: `let x = 5; XCTAssertEqual(x, 5)` or assertions that re-test what the type system already guarantees.
- **Trivial getter/setter coverage** with no logic: `obj.foo = 1; XCTAssertEqual(obj.foo, 1)` for a stored property with no didSet/willSet.
- **Framework re-tests**: tests that exercise standard library or third-party APIs without adding logic of your own (e.g., testing that `Array.count` works).
- **Smoke tests of types** that are already covered by stronger tests elsewhere — duplicates whose deletion wouldn't reduce coverage.
- **Tests that always skip**: `throw XCTSkip(...)` unconditionally, or guarded by an env var that is never set anywhere. Either delete or make conditional skipping explicit and intentional.

For each finding, record file:line, what the test purports to check, why it adds little, and a recommendation (delete / merge into existing test / convert to assertion in a richer test).

### Pass 3 — Coverage gaps

Run real `xccov` data, don't eyeball it. Reasoning from "this file has no XTests file next to it" misses tests that cover code from a distance and over-flags trivial files.

**Generating coverage:**

```bash
# Pick a build dir that won't collide with normal builds
DERIVED=$(mktemp -d)/dd

xcodebuild test \
  -scheme <SCHEME> \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:<CI-safe suites> \  # use the same set the project uses for CI
  2>&1 | tail -50

XCRESULT=$(ls -td "$DERIVED"/Logs/Test/*.xcresult | head -1)

# Human-readable summary
xcrun xccov view --report "$XCRESULT"

# Machine-readable JSON for analysis
xcrun xccov view --report --json "$XCRESULT" > /tmp/coverage.json
```

If the repo has a Makefile target like `make test-coverage` or `make coverage`, prefer it. If `make test` exists, look at how it invokes xcodebuild and add `-enableCodeCoverage YES` + `-derivedDataPath` to that invocation.

**What to extract from the JSON:**

- Per-file line coverage percentage
- Per-function coverage where lineCoverage < 0.5

**Filtering:** raw coverage output is noisy. Drop:
- Generated files (`*.generated.swift`, `Resources/*`, `*Mocks*` if mocks)
- Files under `Tests/` themselves
- Files under `.build/`, `Pods/`, `Carthage/`, vendored dependencies
- Trivial files: pure data structs / enums with synthesized conformances (low coverage on these is uninteresting)

**What's "significant":** a low-coverage file is worth flagging when it's also load-bearing — public API surface, core algorithms, error paths, or anything the user depends on for correctness. A 0%-covered 8-line internal helper isn't worth a finding; a 5%-covered 600-line model loader is.

For each finding, record file path, line coverage, top uncovered functions, and why it matters (public API / hot path / error handling).

### Pass 4 — Flaky-in-CI predictions

Look for the patterns that produce intermittent CI failures. Each finding should name the smell, not just the file:

- **Real-time sleeps for synchronization**: `Thread.sleep`, `usleep`, `try await Task.sleep` used to wait for an event rather than waiting on the event itself. Replace with `XCTestExpectation`, `await`, or a polling helper.
- **Wall-clock assertions**: `XCTAssertEqual(elapsed, 0.5, accuracy: 0.05)` will fail under CI load. Performance assertions belong in measure blocks, not in correctness tests.
- **Nondeterministic input without a seed**: `Int.random(in:)`, `UUID()`, `Date()` baked into the assertion path without seeding or freezing.
- **Order-dependent tests**: tests that mutate shared state (singletons, on-disk caches, `UserDefaults.standard`) without resetting it in `setUp`/`tearDown`. Run-order changes between Xcode versions and parallelization settings.
- **Network in correctness tests**: tests that hit a real URL without an offline fallback or stub. Even when "the URL is stable", DNS, TLS, and rate limits make this flaky.
- **Filesystem race**: tests that write to a fixed path (e.g., `/tmp/foo.txt`) instead of a per-test temp dir, or don't clean up.
- **Concurrency without explicit synchronization**: `DispatchQueue.global().async { ... }` followed by an immediate assertion, or actor-isolated state read across actors without `await`.
- **Timing-sensitive throttles / debounces**: tests that depend on the system clock advancing a specific amount.

If the project already excludes a category from CI (e.g., `MLXAUDIO_NETWORK_TESTS=1`-gated tests), don't flag those — they're correctly gated already. The Pass 4 question is: *of the tests that DO run in CI*, which look risky?

For each finding: file:line, smell, why it'll flake, recommended fix or "nominate for removal" if the test isn't worth saving.

### Pass 5 — Performance tests gating

Performance tests should never run in CI's main correctness lane — they take wall time, give signal that's noisy on shared runners, and don't catch correctness regressions.

**Find perf tests:**
- XCTest: `func test...` containing `measure { }` or `measure(metrics:)`
- swift-testing: `@Test` with `.timeLimit(...)` used as a benchmark, or files named `*PerformanceTests`, `*Benchmark*`, `*Perf*`
- Custom timing harnesses: tests that assert on duration

**Check whether each is excluded from CI:**
- Read CI workflow files (`.github/workflows/*.yml`) and find the test invocation
- Compare `-only-testing:` allowlist or `-skip-testing:` denylist against the perf test target/class
- If the workflow uses `make test`, follow that into the Makefile and check what it actually runs
- Tests guarded by an env var (`if ProcessInfo.processInfo.environment["RUN_PERF"] != nil`) are properly gated *if* the CI workflow doesn't set that var

For each perf test that DOES run in CI: file path, test name, estimated wall-time impact if known, and recommendation (move to a separate `perf` scheme / add to `-skip-testing` / gate behind env var that CI doesn't set).

Also flag the inverse problem briefly: if a Makefile or workflow defines a `perf` target that isn't being run anywhere, mention it under "consolidated actions" so the user can decide whether to wire it up.

## Output: the markdown report

Produce ONE file: `TEST_ANALYSIS.md` in the repo root (or a path the user specifies).

**If `TEST_ANALYSIS.md` already exists, reconcile it against the current codebase rather than overwriting blindly.** A prior report represents the user's working punch list — they may have already acted on some items, others may have rotted, and new ones may have appeared since. Treat the existing file as input, not as something to discard.

Reconciliation procedure:

1. **Read the existing file** before running any pass. Parse it into a list of findings keyed by `(pass, file:line, smell)` so you can match against fresh findings.
2. **Run all five passes normally** to produce a fresh finding set.
3. **Diff the two sets**:
   - **Keep**: a finding present in both — the issue still exists. Carry over any user annotations (a `> note: ...` blockquote, a checkbox, a "won't fix" tag) verbatim.
   - **Delete**: a finding in the old report that no fresh pass produced — the test was removed, the file was deleted, the lint smell is gone, coverage rose above the threshold. Drop it from the new report. If the user had an annotation on it, mention the deletion in a small "Resolved since last run" subsection at the end of each pass so they get credit/context, but don't keep it in the active list.
   - **Add**: a finding the fresh pass produced that wasn't in the old report. Insert it.
   - **Update**: a finding present in both but with changed details (line number drifted, coverage percentage changed, severity moved). Overwrite the details, keep the annotation.
4. **Write the merged result** back to `TEST_ANALYSIS.md`. Mention in the executive summary's narrative that you reconciled against a prior report (e.g., "Updated from previous report dated 2026-04-15 — N findings resolved, M new, K updated").
5. **Stamp a fresh date and git branch/SHA** so it's clear when the reconciliation happened.

If the existing file is malformed or doesn't follow the schema below (e.g., it's a hand-written doc that happens to share the name), don't try to parse it — ask the user whether to overwrite or write to a different filename.

Use this exact structure so the report is consistent across runs and easy to diff over time:

```markdown
# Test Analysis Report

**Repository**: <name>
**Branch**: <git branch>
**Date**: <ISO date>
**Test scheme**: <scheme>
**Tests considered**: <N test suites, M test functions>

## Executive summary

| Pass | Findings | Highest priority item |
|------|----------|------------------------|
| 1. High-repetition tests | <N> | <one-line> |
| 2. Superfluous tests | <N> | <one-line> |
| 3. Coverage gaps | <N files> | <one-line> |
| 4. Flaky-in-CI predictions | <N> | <one-line> |
| 5. Performance gating | <N issues> | <one-line> |

<2-3 sentence narrative summary of the overall health and the single most impactful change to make.>

## Pass 1 — High-repetition tests

### Copy-paste patterns
- `path/to/File.swift:42-78` — `testA`, `testB`, `testC` share identical setup; recommend table-driven helper.
  - **Action**: refactor

### High-iteration loops
- `path/to/File.swift:120` — loops 10,000×; one call would suffice for determinism check.
  - **Action**: reduce N to 1, or move to perf target

## Pass 2 — Superfluous tests
- `path/to/VersionTests.swift:12` — asserts `MyLib.version == "1.2.3"`; auto-passes after every bump.
  - **Action**: delete

## Pass 3 — Coverage gaps

Coverage was measured by running `<command used>` and parsing `xccov` output. Generated, vendored, and trivial files are excluded.

| File | Line coverage | Why it matters | Top uncovered |
|------|---------------|----------------|---------------|
| Sources/Foo/ModelLoader.swift | 12% | Public API; load-failure paths | `loadFromDisk`, `validateChecksum` |

## Pass 4 — Flaky-in-CI predictions
- `path/to/Tests/X.swift:55` — `Thread.sleep(0.1)` used as sync barrier.
  - **Smell**: real-time sleep
  - **Action**: replace with `XCTestExpectation` / nominate for removal

## Pass 5 — Performance test gating
- `path/to/Tests/PerfTests.swift` runs in `make test` and consumes ~90s.
  - **Action**: add `-skip-testing:MLXAudioTests/PerfTests` to CI invocation, keep in a `make test-perf` target.

## Consolidated action items

### Delete
- <bulleted file:line list>

### Refactor
- <bulleted file:line list>

### Gate / move out of CI
- <bulleted file:line list>

### Add tests for
- <bulleted file list with rationale>
```

Keep the report tight. If a pass has zero findings, say "No findings." under that section — don't pad. If a pass couldn't run (e.g., coverage build failed), say so explicitly under that section with the error and what blocked it; don't silently omit.

## How to actually do this efficiently

The repo will be too large to read linearly. A workable order:

1. **Orient (1 minute)**: read `CLAUDE.md`, `AGENTS.md`, `Makefile`, `Package.swift`, and the CI workflow file. Note the scheme name, the CI test allowlist, and any documented gating env vars. This single pass informs all five.
2. **Run `make lint` (Step 0)**. Wait for it to finish before doing anything else — its outcome gates the run.
3. **Kick off coverage in the background** (`run_in_background: true`) immediately after lint passes — it's the long pole. Move on to passes 1, 2, 4, 5 while it runs. Capture the JSON path so you can analyze it when the build finishes.
4. **Static passes (1, 2, 4, 5)**: glob the test directory, then use `grep` to find the specific patterns each pass cares about (e.g., `Thread.sleep`, `measure {`, `for _ in 0\.\.<[0-9]{4,}`, `version`). Read the matching files in batches, parallelizing reads when independent. Don't try to read every test file end-to-end; the patterns are the entry points.
5. **Pull coverage results** when the background task notifies completion. Filter, sort, and pick the load-bearing low-coverage files.
6. **Compose the report**. Sort findings within each pass by impact (delete-able first, then high-effort refactors). Cross-reference: a perf test that's also a flaky candidate should appear in Pass 5 (gating fixes it) and be cross-referenced from Pass 4, not double-counted.

## What NOT to do

- Don't propose edits without specific file:line references. "Some tests are flaky" is useless; `Tests/X.swift:55` is actionable.
- Don't run `swift test` or `swift build` — this project (and most Swift projects with Makefiles) uses `xcodebuild`.
- Don't recommend deletion of a test you don't understand. If a test's purpose is unclear, flag it as "investigate" rather than "delete" — the user knows the project history better than the analysis does.
- Don't conflate low coverage with "needs more tests". A file may have low coverage because it's deprecated, vendored, or generated. The "why it matters" column is what separates a real gap from noise.
- Don't auto-edit the codebase. The output is the report; the user decides what to act on. The single exception is `make lint` in Step 0 — invoking that target is allowed even though a linter may rewrite files as a side effect; running `make lint` is the only code-touching action this skill performs. Do not implement any of your own findings yourself, no matter how trivial they look (e.g., even deleting an obviously dead version-string test). Editing on the analyst's behalf undermines the point — the report needs to be the artifact the user reviews and acts on, not a fait accompli.
- Don't skip writing the report when only one pass succeeded. A partial report with explicit gaps is more useful than no report.
