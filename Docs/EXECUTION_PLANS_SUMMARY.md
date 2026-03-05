# Execution Plans Summary - Custom-Pages Removal

**Created**: 2026-02-15
**Source**: CUSTOM_PAGES_REMOVAL_REQUIREMENTS.md breakdown into repository-specific plans

---

## Overview

The custom-pages.json removal work has been broken down into **three repository-specific execution plans**, each containing only the work relevant to that specific repository.

---

## Created Execution Plans

### 1. SwiftProyecto - Foundation (Phase 0) ⚠️ BLOCKING

**Location**: `/Users/stovak/Projects/SwiftProyecto/EXECUTION_PLAN.md`
**Status**: Ready for execution
**Timeline**: Week 1 (5 sprints)
**Priority**: MUST COMPLETE FIRST

**Work Units**: 1 (SwiftProyecto Foundation)
**Sprints**:
1. ProjectDiscovery Service Implementation
2. ProjectDiscovery Read Cast API
3. ProjectMarkdownParser Write Method & ProjectFrontMatter Helpers
4. Comprehensive Unit Tests
5. Documentation Updates & Release Preparation

**Critical Deliverables**:
- ✅ `ProjectDiscovery.findProjectMd()` with episodes folder detection
- ✅ `ProjectDiscovery.readCast()` with provider filtering
- ✅ `ProjectMarkdownParser.write()` for atomic file writes
- ✅ `ProjectFrontMatter.mergingCast()` for additive voice merging
- ✅ Complete unit tests (100% coverage)
- ✅ AGENTS.md updated with API documentation
- ✅ SwiftProyecto v3.1.0+ tagged and released

**Blocks**: All other phases (SwiftCompartido Phase 2, Produciesta Phase 3)

---

### 2. SwiftCompartido - Cleanup (Phase 2) ⚡ CAN RUN IN PARALLEL

**Location**: `/Users/stovak/Projects/SwiftCompartido/EXECUTION_PLAN.md`
**Status**: Ready for execution
**Timeline**: Week 1-3 (3 sprints)
**Priority**: Independent cleanup - can run in parallel with SwiftProyecto Phase 0

**Work Units**: 1 (SwiftCompartido Cleanup)
**Sprints**:
1. GuionParsedScreenplay Cleanup
2. Test Cleanup & CastListPage Deprecation
3. Documentation Updates & Release

**Critical Deliverables**:
- ✅ Remove all custom-pages.json methods
- ✅ Delete disabled test files
- ✅ Deprecate CastListPage (keep for Highland compatibility)
- ✅ Archive old documentation
- ✅ SwiftCompartido v2.5.0+ tagged and released

**Parallel Execution**: ⚡ This phase can run in parallel with SwiftProyecto Phase 0 (independent cleanup)

---

### 3. Produciesta - Integration & Cleanup (Phase 3) ⚠️ DEPENDS ON SwiftProyecto v3.1.0+

**Location**: `/Users/stovak/Projects/Produciesta/NEXT_EXECUTION_PLAN.md`
**Status**: Not started - Blocked by SwiftProyecto v3.1.0+
**Timeline**: Week 2-5 (6 sprints)
**Priority**: Can only start after SwiftProyecto Phase 0 complete

**Note**: Produciesta already has an active EXECUTION_PLAN.md for VoxAlta Integration. The custom-pages removal work is in NEXT_EXECUTION_PLAN.md. See `EXECUTION_PLAN_REVIEW.md` for priority analysis.

**Work Units**: 1 (Produciesta Integration & Cleanup)
**Sprints**:
1. Dependency Update & Preparation (Phase 1)
2. ProjectMdSyncService Integration
3. CastingView Import/Export Removal
4. AppleScript Automation Updates
5. Shell Script Updates
6. Documentation Updates & Release

**Critical Deliverables**:
- ✅ Update to SwiftProyecto v3.1.0+
- ✅ Replace ProjectMdSyncService with SwiftProyecto API
- ✅ Remove all import/export UI
- ✅ Update AppleScript automation
- ✅ Update shell scripts
- ✅ Add TODO markers for auto-loading improvements
- ✅ Migration guide documentation

**Dependencies**: SwiftProyecto v3.1.0+, SwiftCompartido v2.5.0+

---

## Execution Sequence

### Recommended Timeline

```
Week 1: SwiftProyecto Phase 0 (Sprints 1-5)
        + (Parallel) SwiftCompartido Phase 2 (Sprints 1-3)
        + (Parallel) Produciesta VoxAlta Integration (current EXECUTION_PLAN.md)

Week 2: SwiftProyecto Phase 0 completion & v3.1.0 release
        SwiftCompartido Phase 2 completion & v2.5.0 release
        Produciesta Phase 1 (Sprint 1 - Dependency Update)

Week 3: (Prep week if needed)

Week 4-5: Produciesta Phase 3 (Sprints 2-6 - Integration & Cleanup)

Week 6: Phase 4 (Final documentation review)

Week 7: Phase 5 (Release and announcement)
```

### Parallel Execution Opportunities

**Week 1 Parallelism**:
- ⚡ SwiftProyecto Phase 0 (foundation work)
- ⚡ SwiftCompartido Phase 2 (independent cleanup)
- ⚡ Produciesta VoxAlta Integration (E2E testing - current EXECUTION_PLAN.md)

**Time Saved**: 1-2 weeks by running SwiftCompartido cleanup in parallel

---

## Dependency Graph

```
SwiftProyecto Phase 0 (Week 1) ─┬─► Produciesta Phase 1 (Week 2)
                                 │
                                 └─► Produciesta Phase 3 (Week 4-5)
                                      │
                                      └─► Phase 4-5 (Week 6-7)

SwiftCompartido Phase 2 (Week 1-3) ─► (Independent, no blocking)
```

---

## AGENTS.md Updates

Each execution plan includes specific AGENTS.md updates for that repository:

### SwiftProyecto AGENTS.md
**New Section**: "PROJECT.md Modification Rules"
- API documentation (findProjectMd, readCast, write, mergingCast)
- Ownership boundaries (SwiftProyecto vs client projects)
- Usage examples
- Cast merging examples (voice preservation)

### SwiftCompartido AGENTS.md
**Updates**: Cast Management section
- Deprecate custom-pages.json approach
- Reference SwiftProyecto for cast management
- Migration guide from custom-pages.json

### Produciesta AGENTS.md
**Updates**: Cast Management section
- Current approach (PROJECT.md via SwiftProyecto)
- Known issues & future work (TODO markers)
- Removed features (custom-pages.json import/export)
- Migration guide

---

## Critical Success Criteria (All Phases)

### SwiftProyecto Phase 0
- [ ] Episodes folder detection works (case-insensitive)
- [ ] Cast merging preserves other provider voices (additive, not replace)
- [ ] Complete read/write API (findProjectMd, readCast, write, mergingCast)
- [ ] 100% test coverage on ProjectDiscovery
- [ ] AGENTS.md documented with clear API boundaries
- [ ] v3.1.0 tagged and released

### SwiftCompartido Phase 2
- [ ] All custom-pages.json code removed
- [ ] CastListPage deprecated (kept for Highland compatibility)
- [ ] Tests pass after removal
- [ ] Documentation updated with migration guide
- [ ] v2.5.0 tagged and released

### Produciesta Phase 3
- [ ] SwiftProyecto v3.1.0+ integrated
- [ ] ProjectMdSyncService uses SwiftProyecto API
- [ ] Episodes folder detection works (writes to parent)
- [ ] Cast merging preserves other provider voices
- [ ] All import/export UI removed
- [ ] AppleScript and shell scripts updated
- [ ] Documentation includes migration guide
- [ ] TODO markers added for auto-loading improvements

---

## Special Note: Produciesta Execution Plan Conflict

Produciesta has **TWO execution plans**:

1. **EXECUTION_PLAN.md**: VoxAlta Integration (current, in progress)
2. **NEXT_EXECUTION_PLAN.md**: Custom-Pages Removal (new, blocked)

**Review Document**: `Produciesta/EXECUTION_PLAN_REVIEW.md` provides analysis and recommends:
- Execute VoxAlta Integration FIRST (no blockers, ready now)
- Execute Custom-Pages Removal AFTER (blocked on SwiftProyecto v3.1.0+)
- No file conflicts - could run in parallel once unblocked

---

## Next Steps

### For SwiftProyecto
1. Review `/Users/stovak/Projects/SwiftProyecto/EXECUTION_PLAN.md`
2. Start Sprint 1: ProjectDiscovery Service Implementation
3. Aim for v3.1.0 release by end of Week 1

### For SwiftCompartido
1. Review `/Users/stovak/Projects/SwiftCompartido/EXECUTION_PLAN.md`
2. Start Sprint 1: GuionParsedScreenplay Cleanup (can run in parallel)
3. Aim for v2.5.0 release by end of Week 2-3

### For Produciesta
1. Review `/Users/stovak/Projects/Produciesta/EXECUTION_PLAN_REVIEW.md`
2. Complete VoxAlta Integration (EXECUTION_PLAN.md) first
3. Wait for SwiftProyecto v3.1.0+ release
4. Then start Custom-Pages Removal (NEXT_EXECUTION_PLAN.md)

---

## Files Created

1. `/Users/stovak/Projects/SwiftProyecto/EXECUTION_PLAN.md`
2. `/Users/stovak/Projects/SwiftCompartido/EXECUTION_PLAN.md`
3. `/Users/stovak/Projects/Produciesta/NEXT_EXECUTION_PLAN.md`
4. `/Users/stovak/Projects/Produciesta/EXECUTION_PLAN_REVIEW.md`
5. `/Users/stovak/Projects/package-collection/EXECUTION_PLANS_SUMMARY.md` (this file)

---

**Status**: Ready for review and execution
**Recommendation**: Start SwiftProyecto Phase 0 immediately (blocking work)
**Parallel Work**: SwiftCompartido Phase 2 can start immediately (independent)
**Blocked Work**: Produciesta Phase 3 waits for SwiftProyecto v3.1.0+ release
