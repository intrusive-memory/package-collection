# Conflicts Resolved in CUSTOM_PAGES_REMOVAL_REQUIREMENTS.md

## Summary of Changes

All 8 identified conflicts have been resolved based on user decisions:
1. ✅ readCastFromProjectMd() - YES, add to Phase 0
2. ✅ Auto-loading scope - Basic = Phase 0, Advanced = Future
3. ✅ Phase 2 parallel execution - YES
4. ✅ readCast() API - YES, add to SwiftProyecto

---

## ✅ CONFLICT 1: Auto-Loading Scope - RESOLVED

**Before**: "Issue #2: Fix PROJECT.md Auto-Loading (Separate Action) ... DO NOT MIX THESE"

**After**: Split into two clear scopes:
- **Basic Auto-Loading (Phase 0 - THIS WORK)**:
  - ✅ PROJECT.md discovery with episodes detection
  - ✅ Cast reading and writing API
  - ✅ Provider-specific cast merging
  - ✅ Atomic file writes

- **Advanced Auto-Loading (Future Work)**:
  - ⏭️ SwiftData timing optimization
  - ⏭️ Advanced provider matching
  - ⏭️ Error reporting
  - ⏭️ External change detection

**Result**: Clear separation - basic infrastructure is Phase 0, advanced features are future work.

---

## ✅ CONFLICT 2: Episodes Detection - RESOLVED

**Before**: "Fix: Separate action (mark as TODO in this removal)"

**After**: "Fix: ✅ Implemented in Phase 0 - SwiftProyecto `ProjectDiscovery.findProjectMd()`"

**Result**: Episodes detection is part of Phase 0, not separate work.

---

## ✅ CONFLICT 3: Cast Merging - RESOLVED

**Before**: "Fix: Merge new voices with existing voices per character (separate action)"

**After**: "Fix: ✅ Implemented in Phase 0 - SwiftProyecto `ProjectFrontMatter.mergingCast(forProvider:)`"

**Result**: Cast merging is part of Phase 0, not separate work.

---

## ✅ CONFLICT 4: readCastFromProjectMd() - RESOLVED

**Before**: Not included in Phase 0 requirements, marked "TODO: Phase 2"

**After**: Added to Phase 0 implementation:

```swift
/// Read cast list from PROJECT.md
public func readCast(
    from projectMdURL: URL,
    filterByProvider providerID: String? = nil
) throws -> [CastMember]
```

**Test Coverage Added**:
- Read all cast members
- Read filtered by provider
- Handle no cast scenario
- Empty PROJECT.md handling

**Result**: Complete read/write API in Phase 0.

---

## ✅ CONFLICT 5: API Ownership - RESOLVED

**Before**: "Only SwiftProyecto may modify PROJECT.md files" (confusing about services in other projects)

**After**: Added clarification:
- **SwiftProyecto owns**: File format, parsing, serialization, file I/O, discovery
- **Client projects own**: Business logic, UI, data models, when to call SwiftProyecto API
- **Services like ProjectMdSyncService**: ALLOWED in client projects - they coordinate when to call API

**Forbidden Operations**: Direct file I/O (bypassing SwiftProyecto API)

**Result**: Clear ownership boundaries - using SwiftProyecto API is correct, direct file I/O is not.

---

## ✅ CONFLICT 6: Episodes Folder Test Case - RESOLVED

**Before**: Comment said "should never contain PROJECT.md" but test created one

**After**: Updated comment to: "Edge case: PROJECT.md in episodes folder (unusual but defensively handle it)"

**Result**: Test is valid defensive programming - handles unexpected cases gracefully.

---

## ✅ CONFLICT 7: Phase 2 Parallel Execution - RESOLVED

**Before**: Phase 2 appeared sequential after Phase 1

**After**: "Phase 2: SwiftCompartido Cleanup (Week 1-3) ⚠️ CAN RUN IN PARALLEL"

Added note: "This phase is independent - it can start immediately and run in parallel with Phase 0-1."

Updated dependency table:
| Component | Depends On | Can Run In Parallel? |
|-----------|-----------|---------------------|
| SwiftProyecto | None | N/A (Phase 0) |
| SwiftCompartido | None | ✅ YES (independent cleanup) |
| Produciesta | SwiftProyecto v3.1.0+ | No (must wait for Phase 0) |

**Result**: Phase 2 can start immediately - saves time on the critical path.

---

## ✅ CONFLICT 8: "Phase 2" Terminology - RESOLVED

**Before**: "Phase 2" used for both rollout phase AND future work

**After**: Changed all future work references:
- "Remove in Phase 2 if Highland..." → "Remove in future release if Highland..."
- "Revisit in Phase 2 if..." → "Revisit in future release if..."

**Result**: "Phase 2" now only refers to the rollout phase (SwiftCompartido cleanup), avoiding confusion.

---

## Updated Phase 0 Requirements

### Added to Phase 0:

1. **`ProjectDiscovery.readCast()`**
   - Read cast from PROJECT.md
   - Optional provider filtering
   - Returns `[CastMember]`

2. **Test Coverage**
   - Read cast tests (all, filtered, empty)
   - Episodes folder edge cases
   - 100% coverage on discovery and reading

3. **Documentation Clarifications**
   - Ownership boundaries
   - API usage examples
   - What's allowed vs forbidden

### Phase 0 Checklist:
- [x] findProjectMd() - episodes detection
- [x] readCast() - with provider filtering ← **NEW**
- [x] write() - atomic writes
- [x] withCast() - replace helper
- [x] mergingCast() - additive merge
- [x] Comprehensive tests ← **EXPANDED**
- [x] AGENTS.md documentation ← **CLARIFIED**
- [ ] Tag SwiftProyecto v3.1.0+

---

## Impact on Timeline

### Before (Sequential):
```
Week 1: Phase 0 (SwiftProyecto)
Week 2: Phase 1 (Preparation)
Week 3: Phase 2 (SwiftCompartido)  ← Must wait
Week 4-5: Phase 3 (Produciesta)
Week 6: Phase 4 (Documentation)
Week 7: Phase 5 (Release)
```

### After (Parallel):
```
Week 1: Phase 0 (SwiftProyecto) + Phase 2 (SwiftCompartido in parallel)
Week 2: Phase 1 (Preparation)
Week 3: Phase 2 (SwiftCompartido continues if needed)
Week 4-5: Phase 3 (Produciesta)
Week 6: Phase 4 (Documentation)
Week 7: Phase 5 (Release)
```

**Time Saved**: Potentially 1-2 weeks if Phase 2 completes during Phase 0-1.

---

## What's Still Future Work (Not Phase 0)

These remain as TODO markers for future implementation:

1. **SwiftData Timing Optimization**
   - Race conditions when loading cast
   - Proper actor isolation
   - Structured concurrency improvements

2. **Advanced Provider Matching**
   - Voice URI validation edge cases
   - Provider-specific error handling
   - Fallback voice selection

3. **Error Reporting**
   - User-facing error messages
   - Recoverable vs fatal errors
   - Logging and diagnostics

4. **External Change Detection**
   - File watcher for PROJECT.md changes
   - Auto-sync when file changes outside app
   - Conflict resolution UI

---

## Document Status

✅ **All conflicts resolved**
✅ **Requirements clarified**
✅ **API complete (read + write)**
✅ **Parallel execution enabled**
✅ **Terminology consistent**

**Ready for**: Sprint Supervisor breakdown and task assignment

---

**Last Updated**: 2026-02-15
**Conflicts Resolved**: 8/8
**Status**: ✅ Ready for Implementation
