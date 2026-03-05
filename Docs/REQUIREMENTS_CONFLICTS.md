# Requirements Conflicts in CUSTOM_PAGES_REMOVAL_REQUIREMENTS.md

## Critical Conflicts Identified

---

### ⚠️ CONFLICT 1: Issue #2 Says "Separate Action" But We're Implementing It

**Location**: Lines 23-32 vs Prerequisites Section

**Contradiction**:
- **Lines 23-32**: "Issue #2: Fix PROJECT.md Auto-Loading (Separate Action) ... **⚠️ DO NOT MIX THESE**: This removal plan only deletes custom-pages code. Auto-loading fixes are separate."
- **Prerequisites Section (Lines 95+)**: Implements `findProjectMd()`, `mergingCast()`, episodes detection - **these ARE auto-loading fixes**

**Problem**: The document explicitly says auto-loading is a separate issue, then immediately implements auto-loading functionality as prerequisites.

**Resolution Needed**:
- **Option A**: Auto-loading IS part of this work (Phase 0) - Remove "Separate Action" messaging
- **Option B**: Auto-loading is truly separate - Remove Prerequisites section, just mark TODOs
- **Recommended**: Option A - We need the foundation, so make it clear it's part of this work

---

### ⚠️ CONFLICT 2: Episodes Folder Fix - Separate or Implemented?

**Location**: Lines 54 vs Requirement 1

**Contradiction**:
- **Line 54**: "**Fix**: Separate action (mark as TODO in this removal)"
- **Requirement 1**: Implements full `findProjectMd()` with episodes detection logic

**Problem**: Issue A says episodes detection is a "separate action" but Requirement 1 provides complete implementation.

**Resolution Needed**:
- If implementing in Phase 0 → Remove "Separate action" note from Issue A
- If separate → Remove episodes detection from Requirement 1
- **Recommended**: Implement in Phase 0 (it's foundational), update Issue A to say "Fixed in Phase 0"

---

### ⚠️ CONFLICT 3: Cast Merging - Separate or Implemented?

**Location**: Lines 89 vs Requirement 3

**Contradiction**:
- **Line 89**: "**Fix**: Merge new voices with existing voices per character (separate action)"
- **Requirement 3**: Implements `mergingCast()` helper with full merge logic

**Problem**: Issue B says cast merging is a "separate action" but Requirement 3 provides complete implementation.

**Resolution Needed**:
- If implementing in Phase 0 → Remove "Separate action" note from Issue B
- If separate → Remove `mergingCast()` from Requirement 3
- **Recommended**: Implement in Phase 0 (prevents data loss), update Issue B to say "Fixed in Phase 0"

---

### ⚠️ CONFLICT 4: readCastFromProjectMd() - Implement or Leave as TODO?

**Location**: Line 1330-1337 vs Phase 0 Requirements

**Contradiction**:
- **Current Code**: `readCastFromProjectMd()` marked "TODO: Phase 2 - Implement reading from PROJECT.md"
- **Phase 0 Requirements**: Don't include implementing `readCastFromProjectMd()`
- **But**: We're implementing `findProjectMd()`, `mergingCast()`, `write()` - seems incomplete without `read()`

**Problem**: If we're building the foundation, shouldn't reading from PROJECT.md be part of it?

**Resolution Needed**:
- **Option A**: Add `readCastFromProjectMd()` implementation to Phase 0
- **Option B**: Explicitly state Phase 0 only handles WRITING, reading is Phase 2
- **Question**: Can Produciesta use PROJECT.md without reading capability? Or will it continue using SwiftData until read is implemented?

**Recommended**: Add to Phase 0 requirements - complete the read/write API together

---

### ⚠️ CONFLICT 5: ProjectMdSyncService Location - Who Owns PROJECT.md?

**Location**: Requirement 2 vs Requirement 5

**Contradiction**:
- **Requirement 2**: "**CRITICAL RULE**: Only SwiftProyecto may modify PROJECT.md files."
- **Requirement 5**: Shows Produciesta's `ProjectMdSyncService` writing to PROJECT.md (even via SwiftProyecto API)

**Problem**: If only SwiftProyecto should modify PROJECT.md, why does Produciesta have a service dedicated to PROJECT.md sync?

**Resolution Needed**:
- **Option A**: ProjectMdSyncService should move to SwiftProyecto, Produciesta just calls it
- **Option B**: Clarify that "modify" means "direct file I/O" - using SwiftProyecto API is allowed
- **Recommended**: Option B - Update language to "Only SwiftProyecto should perform direct file I/O on PROJECT.md"

---

### ⚠️ CONFLICT 6: Test Case - Episodes Folder Should Never Contain PROJECT.md

**Location**: Requirement 1 - Test Suite

**Contradiction**:
- **Code comment** (line ~1460 in findProjectMd): "Episodes folder should never contain PROJECT.md directly"
- **Test case** `episodesParentPreferredOverCurrent`: Creates PROJECT.md in episodes folder to test priority

**Problem**: If episodes folder should never contain PROJECT.md, why test for it?

**Resolution Needed**:
- **Option A**: Remove test case - episodes folder never has PROJECT.md, so don't test
- **Option B**: Update comment - "Episodes folder should not normally contain PROJECT.md, but if it does, parent is preferred"
- **Recommended**: Option B - Defensive programming (handle unexpected cases)

---

### ⚠️ CONFLICT 7: Phase Dependencies - Can Phase 2 Run in Parallel?

**Location**: Rollout Plan

**Contradiction**:
- **Phase 0**: "⚠️ MUST COMPLETE FIRST" - blocking
- **Phase 2**: SwiftCompartido cleanup - doesn't actually depend on Phase 0
- **Phase 1**: Preparation - depends on Phase 0 (updates Produciesta dependency)

**Problem**: Phase 2 (SwiftCompartido) could run in parallel with Phase 1 since it's just deleting code, not using the new API.

**Resolution Needed**:
- Update rollout plan to show Phase 2 can start immediately (parallel with Phase 0-1)
- Or explain why Phase 2 must wait (e.g., coordination, testing resources)
- **Recommended**: Allow Phase 2 to run in parallel - it's independent cleanup work

---

### ⚠️ CONFLICT 8: Highland Compatibility - Keep or Deprecate CastListPage?

**Location**: SwiftCompartido Cleanup Section

**Contradiction**:
- **Line 818**: "Decision: Keep for now, deprecate in documentation. Revisit in Phase 2 if Highland support is dropped"
- **But**: "Phase 2" already means SwiftCompartido cleanup in the rollout plan
- **Confusion**: Which "Phase 2" - the numbered phase or some future phase?

**Problem**: Ambiguous use of "Phase 2" - rollout phase vs future work.

**Resolution Needed**:
- Clarify: "Keep for now, revisit in future release if Highland support is dropped"
- Don't use "Phase 2" for future work when it's already a rollout phase number
- **Recommended**: Use "Future Phase" or "Highland Deprecation Phase" to avoid confusion

---

## Summary of Conflicts

| Conflict | Current State | Recommended Resolution |
|----------|--------------|----------------------|
| 1. Auto-loading "Separate" vs Implemented | Says separate, implements it | **Remove "separate" messaging** - it's part of Phase 0 |
| 2. Episodes detection | Says separate, implements it | **Remove "separate" note** - it's fixed in Phase 0 |
| 3. Cast merging | Says separate, implements it | **Remove "separate" note** - it's fixed in Phase 0 |
| 4. readCastFromProjectMd() | Marked TODO, not in Phase 0 | **Add to Phase 0** - complete the API |
| 5. ProjectMdSyncService ownership | Conflicts with "only SwiftProyecto" | **Clarify**: Using API is allowed, direct I/O is not |
| 6. Episodes folder test case | Comment says "never", test creates it | **Update comment** - handle unexpected cases |
| 7. Phase 2 dependencies | Marked sequential, could be parallel | **Allow parallel** - SwiftCompartido doesn't depend on Phase 0 |
| 8. "Phase 2" ambiguity | Used for rollout and future work | **Use "Future Phase"** instead |

---

## Recommended Actions

### 1. Clarify Document Scope

**Update Executive Summary** to clearly state:
- This document covers BOTH custom-pages removal AND SwiftProyecto foundation
- Auto-loading IS part of this work (Phase 0), not a separate action
- "Separate Action" only applies to timing issues and advanced auto-loading features NOT covered here

### 2. Update Issue #2 Section

**Replace** "Separate Action" messaging with:
- **Basic auto-loading** (findProjectMd, mergingCast, write) → Phase 0 (THIS WORK)
- **Advanced auto-loading** (SwiftData timing, provider matching edge cases, error reporting) → Future work (TODO markers)

### 3. Add readCastFromProjectMd() to Phase 0

**Include** in Requirement 3:
```swift
/// Read cast from PROJECT.md and convert to CastMember array
///
/// - Parameters:
///   - projectMdURL: URL to PROJECT.md file
///   - providerID: Optional provider to filter by
/// - Returns: Array of CastMember objects
public func readCast(
    from projectMdURL: URL,
    filterByProvider providerID: String? = nil
) throws -> [CastMember]
```

### 4. Clarify API Boundary Language

**Change**: "Only SwiftProyecto may modify PROJECT.md files"
**To**: "Only SwiftProyecto should perform direct file I/O on PROJECT.md files. Other projects must use SwiftProyecto's API."

### 5. Fix Phase Terminology

**Replace** all instances of "Phase 2" meaning "future work" with "Future Phase" or specific names like "Highland Deprecation Phase"

---

## Questions for Resolution

1. **Should readCastFromProjectMd() be part of Phase 0?** (Recommended: Yes)
2. **Should Phase 2 (SwiftCompartido) run in parallel with Phase 0-1?** (Recommended: Yes)
3. **Is auto-loading part of this work or separate?** (Recommended: Basic auto-loading is Phase 0, advanced features are future work)
4. **Should ProjectMdSyncService eventually move to SwiftProyecto?** (Recommended: No, using API from Produciesta is fine)

