# Custom Pages JSON Removal Requirements

## Executive Summary

This document identifies all code that implements casting import/export via `custom-pages.json` files. The old approach stored casting information in separate JSON files (`custom-pages.json` or `{basename}-custom-pages.json`). The **new approach** stores casting in the `PROJECT.md` frontmatter using SwiftProyecto's `CastMember` model.

**Goal**: Remove all `custom-pages.json` import/export code and migrate to PROJECT.md-only storage.

---

## ⚠️ CRITICAL: Two Separate Issues

### Issue #1: Remove Custom-Pages JSON Code (This Document)
**Scope**: Delete all code that reads/writes `custom-pages.json` files
- SwiftCompartido: Sidecar JSON loading/writing
- Produciesta: Import/Export UI, AppleScript automation
- Documentation: Update help files, archive old plans

**Action**: Delete old code, remove UI elements, update docs

---

### Issue #2: PROJECT.md Auto-Loading - Split Scope

**Basic Auto-Loading** (Phase 0 - THIS WORK):
- ✅ PROJECT.md discovery with episodes folder detection
- ✅ Cast reading and writing API
- ✅ Provider-specific cast merging (additive, preserves other providers)
- ✅ Atomic file writes

**Advanced Auto-Loading** (Future Work - NOT This Document):
- ⏭️ SwiftData timing and concurrency optimization
- ⏭️ Advanced voice provider matching edge cases
- ⏭️ Comprehensive error reporting and user feedback
- ⏭️ Auto-sync when PROJECT.md changes externally

**⚠️ SCOPE CLARITY**: This document covers basic auto-loading infrastructure (Phase 0) AND custom-pages removal (Phases 1-5). Advanced auto-loading features are future work and should be marked with TODO.

---

## 🚨 Critical Issues in Current PROJECT.md Implementation

### Issue A: Episodes Folder Not Detected

**Current Behavior** (BROKEN):
```
/project/episodes/chapter-01.fountain
/project/episodes/PROJECT.md  ← Written here (WRONG)
```

**Required Behavior**:
```
/project/episodes/chapter-01.fountain
/project/PROJECT.md  ← Write to parent (CORRECT)
```

**Detection Rule**: If folder name is "episodes" (case-insensitive) → use parent folder
**Code Location**: `ProjectMdSyncService.swift` line 89-90
**Fix**: ✅ Implemented in Phase 0 - SwiftProyecto `ProjectDiscovery.findProjectMd()`

**Note**: SwiftProyecto currently has `episodesDir` configuration (PROJECT.md → episodes folder) but not the reverse (episodes folder → PROJECT.md parent). Phase 0 adds the reverse lookup capability.

---

### Issue B: Cast Export Overwrites Other Providers

**Current Behavior** (BROKEN):
```yaml
# Before: Has ElevenLabs voice
cast:
  - character: NARRATOR
    voices:
      elevenlabs: 21m00Tcm4TlvDq8ikWAM

# User assigns Apple voice → ElevenLabs voice LOST!
cast:
  - character: NARRATOR
    voices:
      apple: com.apple.voice.premium.en-US.Aaron  # ❌ elevenlabs gone!
```

**Required Behavior** (ADDITIVE):
```yaml
# After: Preserves ElevenLabs, adds Apple
cast:
  - character: NARRATOR
    voices:
      apple: com.apple.voice.premium.en-US.Aaron  # ✅ Added
      elevenlabs: 21m00Tcm4TlvDq8ikWAM  # ✅ Preserved
```

**Code Location**: `ProjectMdSyncService.swift` line 128
**Current Code**: `cast: castMembers.isEmpty ? nil : castMembers` (replaces entire array)
**Fix**: ✅ Implemented in Phase 0 - SwiftProyecto `ProjectFrontMatter.mergingCast(forProvider:)`

---

---

## Prerequisites: SwiftProyecto PROJECT.md Foundation

### ⚠️ CRITICAL: Build Foundation First

Before removing custom-pages.json code, we must establish SwiftProyecto as the **single source of truth** for PROJECT.md operations. This ensures all projects have a solid, tested API for PROJECT.md interaction.

**Priority**: This work must be completed FIRST, before custom-pages removal begins.

---

## REQUIREMENT 1: SwiftProyecto findProjectMd() Implementation

### Overview

Create a robust, testable `findProjectMd()` function in SwiftProyecto that handles all PROJECT.md discovery scenarios.

### Location

**New File**: `/Users/stovak/Projects/SwiftProyecto/Sources/SwiftProyecto/Services/ProjectDiscovery.swift`

### API Design

```swift
import Foundation

/// Service for discovering PROJECT.md files in directory hierarchies.
///
/// This is the canonical implementation for PROJECT.md discovery.
/// All projects should use this service instead of implementing their own search logic.
///
/// ## Search Strategy
///
/// 1. **Episodes folder detection**: If starting file is in "episodes" folder → check parent first
/// 2. **Current directory**: Check directory containing the starting file
/// 3. **Parent directory**: Check one level up as fallback
/// 4. **Not found**: Return nil (caller decides error handling)
///
/// ## Example
///
/// ```swift
/// let discovery = ProjectDiscovery()
///
/// // From screenplay file
/// if let projectMdURL = discovery.findProjectMd(from: screenplayURL) {
///     let parser = ProjectMarkdownParser()
///     let (frontMatter, body) = try parser.parse(fileURL: projectMdURL)
/// }
/// ```
public struct ProjectDiscovery: Sendable {

    /// Initialize the discovery service
    public init() {}

    /// Find PROJECT.md file starting from a given file or directory.
    ///
    /// ## Search Order
    ///
    /// 1. If `startingFrom` is in "episodes" folder (case-insensitive):
    ///    - Check parent directory first
    ///    - Example: `/project/episodes/script.fountain` → `/project/PROJECT.md`
    ///
    /// 2. Check current directory:
    ///    - `/project/script.fountain` → `/project/PROJECT.md`
    ///
    /// 3. Check parent directory (fallback):
    ///    - `/project/subdirectory/script.fountain` → `/project/PROJECT.md`
    ///
    /// ## Edge Cases
    ///
    /// - If `startingFrom` is a directory → treats it as the current directory
    /// - If `startingFrom` is a file → uses its parent directory as current
    /// - Case-insensitive folder name matching ("episodes", "Episodes", "EPISODES")
    /// - Stops after parent directory (doesn't recurse to root)
    ///
    /// - Parameter startingFrom: URL to file or directory to start search from
    /// - Returns: URL to PROJECT.md if found, nil otherwise
    public func findProjectMd(from startingFrom: URL) -> URL? {
        // Determine starting directory
        let startingDir: URL
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(
            atPath: startingFrom.path,
            isDirectory: &isDirectory
        )

        if fileExists && isDirectory.boolValue {
            startingDir = startingFrom
        } else {
            // File or doesn't exist → use parent directory
            startingDir = startingFrom.deletingLastPathComponent()
        }

        let folderName = startingDir.lastPathComponent.lowercased()

        // PRIORITY 1: If in "episodes" folder → check parent FIRST
        if folderName == "episodes" {
            let parentDir = startingDir.deletingLastPathComponent()
            if let projectMd = checkDirectory(parentDir) {
                return projectMd
            }
            // Note: Don't check current dir if episodes folder
            // Episodes folder should never contain PROJECT.md directly
        } else {
            // PRIORITY 2: Check current directory
            if let projectMd = checkDirectory(startingDir) {
                return projectMd
            }
        }

        // PRIORITY 3: Check parent directory (fallback)
        let parentDir = startingDir.deletingLastPathComponent()
        if let projectMd = checkDirectory(parentDir) {
            return projectMd
        }

        // Not found
        return nil
    }

    /// Check if PROJECT.md exists in a specific directory
    ///
    /// - Parameter directory: Directory URL to check
    /// - Returns: URL to PROJECT.md if found, nil otherwise
    private func checkDirectory(_ directory: URL) -> URL? {
        let projectMdURL = directory.appendingPathComponent("PROJECT.md")

        guard FileManager.default.fileExists(atPath: projectMdURL.path) else {
            return nil
        }

        return projectMdURL
    }

    /// Read cast list from PROJECT.md
    ///
    /// Parses PROJECT.md and extracts the cast array.
    /// Optionally filters to a specific provider.
    ///
    /// - Parameters:
    ///   - projectMdURL: URL to PROJECT.md file
    ///   - providerID: Optional provider to filter by (e.g., "apple", "elevenlabs")
    /// - Returns: Array of CastMember objects
    /// - Throws: Parsing errors
    ///
    /// ## Example
    ///
    /// ```swift
    /// let discovery = ProjectDiscovery()
    /// if let projectMd = discovery.findProjectMd(from: screenplayURL) {
    ///     // Read all cast members
    ///     let allCast = try discovery.readCast(from: projectMd)
    ///
    ///     // Read only Apple voices
    ///     let appleCast = try discovery.readCast(from: projectMd, filterByProvider: "apple")
    /// }
    /// ```
    public func readCast(
        from projectMdURL: URL,
        filterByProvider providerID: String? = nil
    ) throws -> [CastMember] {
        let parser = ProjectMarkdownParser()
        let (frontMatter, _) = try parser.parse(fileURL: projectMdURL)

        guard let cast = frontMatter.cast else {
            return []
        }

        // Filter by provider if specified
        if let providerID = providerID {
            return cast.filter { member in
                member.voices.keys.contains(providerID)
            }
        }

        return cast
    }
}
```

### Test Requirements

**New File**: `/Users/stovak/Projects/SwiftProyecto/Tests/SwiftProyectoTests/ProjectDiscoveryTests.swift`

```swift
import Testing
import Foundation
@testable import SwiftProyecto

@Suite("ProjectDiscovery Tests")
struct ProjectDiscoveryTests {

    let discovery = ProjectDiscovery()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Episodes Folder Tests

    @Test("Find PROJECT.md from episodes folder - parent location")
    func findFromEpisodesFolder() throws {
        // Setup: /project/PROJECT.md and /project/episodes/script.fountain
        let projectDir = tempDir.appendingPathComponent("project")
        let episodesDir = projectDir.appendingPathComponent("episodes")
        try FileManager.default.createDirectory(at: episodesDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Test\n---".write(to: projectMd, atomically: true, encoding: .utf8)

        let scriptFile = episodesDir.appendingPathComponent("script.fountain")

        // Test: Find from script in episodes folder
        let found = discovery.findProjectMd(from: scriptFile)

        #expect(found == projectMd)
    }

    @Test("Episodes folder case-insensitive - EPISODES")
    func episodesFolderUppercase() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        let episodesDir = projectDir.appendingPathComponent("EPISODES")
        try FileManager.default.createDirectory(at: episodesDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Test\n---".write(to: projectMd, atomically: true, encoding: .utf8)

        let scriptFile = episodesDir.appendingPathComponent("script.fountain")
        let found = discovery.findProjectMd(from: scriptFile)

        #expect(found == projectMd)
    }

    @Test("Episodes folder case-insensitive - Episodes")
    func episodesFolderMixedCase() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        let episodesDir = projectDir.appendingPathComponent("Episodes")
        try FileManager.default.createDirectory(at: episodesDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Test\n---".write(to: projectMd, atomically: true, encoding: .utf8)

        let scriptFile = episodesDir.appendingPathComponent("script.fountain")
        let found = discovery.findProjectMd(from: scriptFile)

        #expect(found == projectMd)
    }

    // MARK: - Current Directory Tests

    @Test("Find PROJECT.md in current directory")
    func findInCurrentDirectory() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Test\n---".write(to: projectMd, atomically: true, encoding: .utf8)

        let scriptFile = projectDir.appendingPathComponent("script.fountain")
        let found = discovery.findProjectMd(from: scriptFile)

        #expect(found == projectMd)
    }

    // MARK: - Parent Directory Tests

    @Test("Find PROJECT.md in parent directory")
    func findInParentDirectory() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        let subDir = projectDir.appendingPathComponent("subdirectory")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Test\n---".write(to: projectMd, atomically: true, encoding: .utf8)

        let scriptFile = subDir.appendingPathComponent("script.fountain")
        let found = discovery.findProjectMd(from: scriptFile)

        #expect(found == projectMd)
    }

    // MARK: - Not Found Tests

    @Test("Return nil when PROJECT.md not found")
    func notFound() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let scriptFile = projectDir.appendingPathComponent("script.fountain")
        let found = discovery.findProjectMd(from: scriptFile)

        #expect(found == nil)
    }

    // MARK: - Edge Case Tests

    @Test("Starting from directory instead of file")
    func startFromDirectory() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Test\n---".write(to: projectMd, atomically: true, encoding: .utf8)

        // Pass directory instead of file
        let found = discovery.findProjectMd(from: projectDir)

        #expect(found == projectMd)
    }

    @Test("Prefers episodes parent over current directory")
    func episodesParentPreferredOverCurrent() throws {
        // Setup: PROJECT.md in both parent and episodes folder
        let projectDir = tempDir.appendingPathComponent("project")
        let episodesDir = projectDir.appendingPathComponent("episodes")
        try FileManager.default.createDirectory(at: episodesDir, withIntermediateDirectories: true)

        let parentProjectMd = projectDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Parent\n---".write(to: parentProjectMd, atomically: true, encoding: .utf8)

        // Edge case: PROJECT.md in episodes folder (unusual but defensively handle it)
        let episodesProjectMd = episodesDir.appendingPathComponent("PROJECT.md")
        try "---\ntitle: Episodes\n---".write(to: episodesProjectMd, atomically: true, encoding: .utf8)

        let scriptFile = episodesDir.appendingPathComponent("script.fountain")
        let found = discovery.findProjectMd(from: scriptFile)

        // Should prefer parent over current (episodes folder)
        #expect(found == parentProjectMd)
    }

    // MARK: - Read Cast Tests

    @Test("Read cast from PROJECT.md")
    func readCastFromProjectMd() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        let content = """
---
title: Test Project
author: Test Author
created: 2025-01-01T00:00:00Z
cast:
  - character: NARRATOR
    actor: Tom Stovall
    voices:
      apple: com.apple.voice.compact.en-US.Aaron
      elevenlabs: 21m00Tcm4TlvDq8ikWAM
  - character: LAO TZU
    voices:
      apple: com.apple.voice.compact.en-US.Fred
---

# Project Notes
"""
        try content.write(to: projectMd, atomically: true, encoding: .utf8)

        // Read all cast
        let allCast = try discovery.readCast(from: projectMd)
        #expect(allCast.count == 2)
        #expect(allCast[0].character == "NARRATOR")
        #expect(allCast[0].voices["apple"] == "com.apple.voice.compact.en-US.Aaron")
        #expect(allCast[0].voices["elevenlabs"] == "21m00Tcm4TlvDq8ikWAM")
    }

    @Test("Read cast filtered by provider")
    func readCastFilteredByProvider() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        let content = """
---
title: Test Project
author: Test Author
created: 2025-01-01T00:00:00Z
cast:
  - character: NARRATOR
    voices:
      apple: com.apple.voice.compact.en-US.Aaron
  - character: LAO TZU
    voices:
      elevenlabs: 21m00Tcm4TlvDq8ikWAM
  - character: COMMENTATOR
    voices:
      apple: com.apple.voice.compact.en-US.Fred
      elevenlabs: abc123
---
"""
        try content.write(to: projectMd, atomically: true, encoding: .utf8)

        // Read only Apple voices
        let appleCast = try discovery.readCast(from: projectMd, filterByProvider: "apple")
        #expect(appleCast.count == 2) // NARRATOR and COMMENTATOR
        #expect(appleCast.contains(where: { $0.character == "NARRATOR" }))
        #expect(appleCast.contains(where: { $0.character == "COMMENTATOR" }))
        #expect(!appleCast.contains(where: { $0.character == "LAO TZU" }))
    }

    @Test("Read cast returns empty array when no cast")
    func readCastNoCast() throws {
        let projectDir = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let projectMd = projectDir.appendingPathComponent("PROJECT.md")
        let content = """
---
title: Test Project
author: Test Author
created: 2025-01-01T00:00:00Z
---
"""
        try content.write(to: projectMd, atomically: true, encoding: .utf8)

        let cast = try discovery.readCast(from: projectMd)
        #expect(cast.isEmpty)
    }
}
```

---

## REQUIREMENT 2: API Boundaries - PROJECT.md Modification Rules

### Single Source of Truth: SwiftProyecto

**CRITICAL RULE**: Only SwiftProyecto may modify PROJECT.md files.

### Public API - What Other Projects Can Do

#### ✅ ALLOWED: Read Operations

```swift
// Find PROJECT.md
let discovery = ProjectDiscovery()
if let projectMdURL = discovery.findProjectMd(from: screenplayURL) {
    // Parse PROJECT.md
    let parser = ProjectMarkdownParser()
    let (frontMatter, body) = try parser.parse(fileURL: projectMdURL)

    // Access data
    let cast = frontMatter.cast
    let episodesDir = frontMatter.episodesDir
}
```

#### ✅ ALLOWED: In-Memory Modifications

```swift
// Create modified front matter
var updatedFrontMatter = frontMatter
updatedFrontMatter = updatedFrontMatter.withCast(newCastMembers)

// Generate content (in-memory)
let parser = ProjectMarkdownParser()
let newContent = parser.generate(frontMatter: updatedFrontMatter, body: body)
```

#### ✅ ALLOWED: Write via SwiftProyecto API

```swift
// Write using SwiftProyecto's API (RECOMMENDED)
let parser = ProjectMarkdownParser()
try parser.write(
    frontMatter: updatedFrontMatter,
    body: body,
    to: projectMdURL
)
```

#### ❌ FORBIDDEN: Direct File I/O on PROJECT.md

```swift
// ❌ NEVER DO THIS - bypass SwiftProyecto for file writes
try newContent.write(to: projectMdURL, atomically: true, encoding: .utf8)

// ❌ NEVER DO THIS - custom PROJECT.md generation
let customContent = "---\ntitle: \(title)\n---\n\(body)"
try customContent.write(to: projectMdURL, atomically: true, encoding: .utf8)

// ❌ NEVER DO THIS - direct file reading (use SwiftProyecto API)
let data = try Data(contentsOf: projectMdURL)
```

**Clarification**: "Modify" means **direct file I/O**. Using SwiftProyecto's API (parse, generate, write) is the correct approach.

### Why This Matters

1. **Validation**: SwiftProyecto validates frontmatter before writing
2. **Format consistency**: YAML serialization handled consistently
3. **Atomic writes**: Prevents corruption from failed writes
4. **Future changes**: SwiftProyecto can evolve PROJECT.md format without breaking clients
5. **Testing**: Centralized logic is easier to test

### Ownership Clarification

**SwiftProyecto owns**:
- PROJECT.md file format specification
- Parsing and serialization logic
- File I/O operations (read, write, atomic writes)
- Discovery and location logic (findProjectMd)

**Client projects (Produciesta, etc.) own**:
- When to read/write PROJECT.md (business logic)
- What data to store (cast assignments, preferences)
- UI for editing metadata
- Integration with their own data models (SwiftData, etc.)

**Services like ProjectMdSyncService**: These are **allowed** in client projects - they coordinate WHEN to call SwiftProyecto's API based on business logic (e.g., "sync cast when voice assignment changes").

---

## REQUIREMENT 3: SwiftProyecto API Extensions

### Add Write Method to ProjectMarkdownParser

**File**: `/Users/stovak/Projects/SwiftProyecto/Sources/SwiftProyecto/Utilities/ProjectMarkdownParser.swift`

**New Method**:

```swift
/// Write PROJECT.md file to disk
///
/// This is the canonical method for writing PROJECT.md files.
/// Use this instead of direct file I/O to ensure proper formatting and atomic writes.
///
/// - Parameters:
///   - frontMatter: Project front matter to serialize
///   - body: Markdown body content (after frontmatter)
///   - url: Destination URL for PROJECT.md file
/// - Throws: Writing errors or YAML serialization errors
public func write(
    frontMatter: ProjectFrontMatter,
    body: String,
    to url: URL
) throws {
    let content = generate(frontMatter: frontMatter, body: body)
    try content.write(to: url, atomically: true, encoding: .utf8)
}
```

### Add Convenience Methods to ProjectFrontMatter

**File**: `/Users/stovak/Projects/SwiftProyecto/Sources/SwiftProyecto/Models/ProjectFrontMatter.swift`

**New Extensions**:

```swift
extension ProjectFrontMatter {

    /// Create a copy with updated cast list
    ///
    /// - Parameter cast: New cast members (replaces existing cast)
    /// - Returns: New ProjectFrontMatter with updated cast
    public func withCast(_ cast: [CastMember]?) -> ProjectFrontMatter {
        ProjectFrontMatter(
            type: self.type,
            title: self.title,
            author: self.author,
            created: self.created,
            description: self.description,
            season: self.season,
            episodes: self.episodes,
            genre: self.genre,
            tags: self.tags,
            episodesDir: self.episodesDir,
            audioDir: self.audioDir,
            filePattern: self.filePattern,
            exportFormat: self.exportFormat,
            cast: cast,
            preGenerateHook: self.preGenerateHook,
            postGenerateHook: self.postGenerateHook,
            tts: self.tts
        )
    }

    /// Merge cast member voices for a specific provider
    ///
    /// Preserves voices for other providers while updating voices for the specified provider.
    ///
    /// - Parameters:
    ///   - newCast: New cast members with voices for the current provider
    ///   - providerID: Provider ID to update (e.g., "apple", "elevenlabs")
    /// - Returns: New ProjectFrontMatter with merged cast
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Existing cast has elevenlabs voices
    /// // newCast has apple voices
    /// let merged = frontMatter.mergingCast(newCast, forProvider: "apple")
    /// // Result: cast members have BOTH apple and elevenlabs voices
    /// ```
    public func mergingCast(_ newCast: [CastMember], forProvider providerID: String) -> ProjectFrontMatter {
        var mergedCast: [CastMember] = self.cast ?? []

        for newMember in newCast {
            // Find existing member by character name
            if let index = mergedCast.firstIndex(where: { $0.character == newMember.character }) {
                // Merge voices (preserve existing, add/update for providerID)
                var existingMember = mergedCast[index]
                var mergedVoices = existingMember.voices

                // Add/update voices for this provider
                if let newVoice = newMember.voices[providerID] {
                    mergedVoices[providerID] = newVoice
                }

                // Update member with merged voices
                mergedCast[index] = CastMember(
                    character: existingMember.character,
                    actor: newMember.actor ?? existingMember.actor,
                    gender: newMember.gender ?? existingMember.gender,
                    voiceDescription: newMember.voiceDescription ?? existingMember.voiceDescription,
                    voices: mergedVoices
                )
            } else {
                // New character - add to cast
                mergedCast.append(newMember)
            }
        }

        return withCast(mergedCast)
    }
}
```

---

## REQUIREMENT 4: Documentation Updates

### SwiftProyecto AGENTS.md

**Add Section**: "PROJECT.md Modification Rules"

```markdown
## PROJECT.md Modification Rules

### Single Source of Truth

**SwiftProyecto is the ONLY package that should modify PROJECT.md files.**

Other projects (Produciesta, podcast generators, etc.) must use SwiftProyecto's API for all PROJECT.md operations.

### Finding PROJECT.md

Use `ProjectDiscovery` service:

```swift
import SwiftProyecto

let discovery = ProjectDiscovery()
if let projectMdURL = discovery.findProjectMd(from: screenplayURL) {
    // Found PROJECT.md
}
```

**Search Logic**:
1. If screenplay is in "episodes" folder → check parent directory first
2. Check current directory
3. Check parent directory (fallback)

### Reading PROJECT.md

```swift
let parser = ProjectMarkdownParser()
let (frontMatter, body) = try parser.parse(fileURL: projectMdURL)

// Access data
let title = frontMatter.title
let cast = frontMatter.cast
```

### Writing PROJECT.md

**CORRECT (Use SwiftProyecto API)**:

```swift
// Modify front matter (in-memory)
let updatedFrontMatter = frontMatter.mergingCast(newCast, forProvider: "apple")

// Write using SwiftProyecto
let parser = ProjectMarkdownParser()
try parser.write(frontMatter: updatedFrontMatter, body: body, to: projectMdURL)
```

**WRONG (Direct File I/O)**:

```swift
// ❌ NEVER DO THIS
let content = parser.generate(frontMatter: updatedFrontMatter, body: body)
try content.write(to: projectMdURL, atomically: true, encoding: .utf8)
```

### Why These Rules Matter

1. **Format consistency** - YAML serialization handled uniformly
2. **Validation** - SwiftProyecto validates before writing
3. **Atomic writes** - Prevents file corruption
4. **Future evolution** - Format can change without breaking clients
```

---

## REQUIREMENT 5: Integration Points for Produciesta

### Update Produciesta/Services/ProjectMdSyncService.swift

**Replace Lines 89-96** with SwiftProyecto API:

```swift
// OLD (Custom logic):
let projectDir = sourceFileURL.deletingLastPathComponent()
let projectMdURL = projectDir.appendingPathComponent("PROJECT.md")

guard FileManager.default.fileExists(atPath: projectMdURL.path) else {
    debugLog("  ℹ️  PROJECT.md not found - skipping write")
    return
}

// NEW (Use SwiftProyecto):
import SwiftProyecto

let discovery = ProjectDiscovery()
guard let projectMdURL = discovery.findProjectMd(from: sourceFileURL) else {
    debugLog("  ℹ️  PROJECT.md not found - skipping write")
    return
}
```

**Replace Lines 128 (Cast Writing)** with merge logic:

```swift
// OLD (Replaces entire cast):
cast: castMembers.isEmpty ? nil : castMembers,

// NEW (Merge cast for current provider):
let parser = ProjectMarkdownParser()
let updatedFrontMatter = frontMatter.mergingCast(castMembers, forProvider: providerID)

// Write using SwiftProyecto API
try parser.write(frontMatter: updatedFrontMatter, body: bodyContent, to: projectMdURL)
```

---

## Architecture Overview

### Old Approach ❌ (To Be Removed)
- **Storage**: Separate `.json` files alongside `.fountain` files
- **Models**: `CastListPage` with `CastMember` items (SwiftCompartido)
- **Format**: Highland 2 compatible JSON with `type`, `id`, `title`, `position`, `printDots`, `items[]`
- **Locations**:
  - `{basename}-custom-pages.json` (document-specific)
  - `custom-pages.json` (shared across multiple .fountain files)
  - Highland bundles: `{bundle}/resources/custom-pages.json`

### New Approach ✅ (Current Standard)
- **Storage**: PROJECT.md YAML frontmatter
- **Models**: SwiftProyecto `CastMember` struct
- **Format**:
  ```yaml
  cast:
    - character: NARRATOR
      actor: Tom Stovall
      gender: M
      voiceDescription: "Deep, warm baritone"
      voices:
        apple: com.apple.voice.compact.en-US.Aaron
        elevenlabs: 21m00Tcm4TlvDq8ikWAM
        voxalta: narrative-1
  ```
- **API**: `ProjectMarkdownParser` for reading/writing

---

## Code Nomination for Removal

### 1. SwiftCompartido Package

#### 1.1 GuionParsedScreenplay.swift
**Location**: `/Users/stovak/Projects/SwiftCompartido/Sources/SwiftCompartido/Sendable/GuionParsedScreenplay.swift`

**Methods to Remove**:

##### Line 696-725: `loadCustomPagesForFile(url:)`
```swift
static func loadCustomPagesForFile(url: URL) -> [CustomPageContainer]
```
- **Status**: Already DISABLED (returns empty array)
- **Purpose**: Loaded sidecar `custom-pages.json` or `{basename}-custom-pages.json`
- **Action**: Delete entire method including disabled code block

##### Line 727-745: `tryLoadCustomPagesJSON(from:)`
```swift
private static func tryLoadCustomPagesJSON(from url: URL) -> [CustomPageContainer]?
```
- **Status**: Implemented but unused (called from disabled code)
- **Purpose**: Helper to parse JSON file into `CustomPageContainer` array
- **Action**: Delete entire method

##### Line 753-769: `writeCustomPagesSidecar(for:)`
```swift
func writeCustomPagesSidecar(for url: URL) throws
```
- **Status**: Already DISABLED (empty return)
- **Purpose**: Wrote `{basename}-custom-pages.json` alongside .fountain file
- **Action**: Delete entire method including disabled code block

**Comments to Remove**:
- Line 216: `// REMOVED: Automatic sidecar loading - customPages must be loaded manually if needed`
- Line 484: `// REMOVED: Automatic sidecar writing - write customPages manually if needed`
- Line 491: `// REMOVED: Automatic sidecar writing - write customPages manually if needed`

**Action**: Remove these comments and any related code that references them.

---

#### 1.2 GuionParsedScreenplay+Highland.swift
**Location**: `/Users/stovak/Projects/SwiftCompartido/Sources/SwiftCompartido/Sendable/GuionParsedScreenplay+Highland.swift`

**Methods to Remove**:

##### Line 93-112: `loadCustomPages(from:)`
```swift
private static func loadCustomPages(from textBundleURL: URL) -> [CustomPageContainer]
```
- **Status**: Implemented but commented out at call site
- **Purpose**: Loaded `custom-pages.json` from Highland .textbundle/resources/
- **Action**: Delete entire method

**Call Sites to Update**:
- Line 79: `// let customPages = Self.loadCustomPages(from: textBundleURL)` - Remove this comment
- Line 86: `customPages: [] // DISABLED` - Remove "// DISABLED" comment, keep empty array or remove parameter

---

#### 1.3 GuionParsedScreenplay+TextBundle.swift
**Location**: `/Users/stovak/Projects/SwiftCompartido/Sources/SwiftCompartido/Sendable/GuionParsedScreenplay+TextBundle.swift`

**Methods to Remove**:

##### Line 174-178: `writeCustomPagesJSON(to:)`
```swift
private func writeCustomPagesJSON(to url: URL) throws
```
- **Status**: Implemented (may still be called from Highland export)
- **Purpose**: Writes custom pages array to `custom-pages.json`
- **Action**: Delete entire method
- **Note**: Check if called from Highland export workflow before deleting

**Investigation Required**:
- Search for calls to `writeCustomPagesJSON` in Highland export methods
- If found, remove those calls as well

---

#### 1.4 CastListPage.swift
**Location**: `/Users/stovak/Projects/SwiftCompartido/Sources/SwiftCompartido/Sendable/CastListPage.swift`

**Decision**: **KEEP** (for now)

**Rationale**:
- This model represents Highland's native cast list format
- May still be needed for Highland file format round-tripping
- SwiftProyecto `CastMember` is the canonical model for PROJECT.md
- Consider deprecating in a future phase if Highland support is dropped

**Action**:
- Add deprecation warning in documentation
- Document migration path to SwiftProyecto `CastMember`
- Remove in future release if Highland import/export is deprecated

---

#### 1.5 Disabled Test Files

**Files to Delete**:
1. `Tests/SwiftCompartidoTests/FountainCustomPagesSidecarTests.swift.disabled`
2. `Tests/SwiftCompartidoTests/HighlandCustomPagesTests.swift.disabled`

**Rationale**:
- Already disabled (`.disabled` extension)
- Test old sidecar JSON functionality
- No longer relevant with PROJECT.md approach

---

#### 1.6 Documentation Files

**File**: `.claude/docs/CUSTOM_PAGES_REQUIREMENTS.md`

**Action**: **ARCHIVE** (move to `.archive/`)

**New Location**: `.archive/2025-02_CUSTOM_PAGES_REQUIREMENTS.md`

**Rationale**:
- Historical reference for Highland custom pages feature
- No longer active requirements
- Keep for context but remove from active documentation

---

### 2. Produciesta Application

#### 2.1 CastingView.swift
**Location**: `/Users/stovak/Projects/Produciesta/Produciesta/CastingView.swift`

**Methods to Remove**:

##### Line 278-279: Auto-import on view load
```swift
// Auto-import custom-pages.json if available
await checkAndAutoImportCastList()
```
- **Action**: Remove this call and the comment
- **Replacement**: Load cast from PROJECT.md via SwiftProyecto instead
- **⚠️ IMPORTANT**: Ensure PROJECT.md auto-loading still works after removal
- **TODO**: Mark PROJECT.md auto-loading code for future fix (separate issue)

##### Line 360-369: `importCastList()`
```swift
private func importCastList() {
    // Shows import dialog/picker
}
```
- **Action**: Delete entire method
- **Replacement**: None (import from PROJECT.md is automatic)

##### Line 521-540: `showSaveDialog(sourceURL:)`
```swift
private func showSaveDialog(sourceURL: URL) async {
    let savePanel = NSSavePanel()
    savePanel.nameFieldStringValue = "custom-pages.json"
    // ...
}
```
- **Action**: Delete entire method
- **Replacement**: Export to PROJECT.md instead

##### Line 542-560: `showImportDialog()`
```swift
private func showImportDialog() async {
    let openPanel = NSOpenPanel()
    openPanel.prompt = "Import Cast List"
    // ...
}
```
- **Action**: Delete entire method

##### Line 564-609+: `processCastListImport(from:)`
```swift
private func processCastListImport(from fileURL: URL) async {
    // Reads custom-pages.json and imports cast members
}
```
- **Action**: Delete entire method (100+ lines)
- **Note**: This is the core import logic - large chunk to remove

##### Line 855-894+: `checkAndAutoImportCastList()`
```swift
private func checkAndAutoImportCastList() async {
    // Checks for custom-pages.json in screenplay directory
}
```
- **Action**: Delete entire method
- **Note**: This auto-imports on view load - critical for automation scripts

**UI Elements to Remove**:
- Import button in toolbar
- Export button in toolbar
- File importers/pickers for JSON files
- Any dialogs/sheets related to custom-pages.json

**Notifications to Remove**:
- `.castImportDidComplete` notification
- Darwin notification: `com.intrusive-memory.Produciesta.importComplete`

**User Defaults to Remove**:
- `automationImportPath` (used by AppleScript automation)

---

#### 2.2 produciesta-cli/GenerateCommand.swift
**Location**: `/Users/stovak/Projects/Produciesta/produciesta-cli/GenerateCommand.swift`

**Investigation Required**:
- Check if CLI references `custom-pages.json` for batch processing
- If found, migrate to PROJECT.md cast loading via SwiftProyecto
- Search for: "custom-pages", "CustomPages", "cast list import"

---

#### 2.3 AppleScript Automation Scripts

**Files to Update**:

##### `scripts/automate-produciesta.applescript`
- Line 62: Comment references auto-import of custom-pages.json
- Line 172-174: `importCastListDirect(customPagesPath)` - Delete function
- Line 492+: `importCastList(customPagesPath)` - Delete function

**Action**:
- Remove all functions that set `automationImportPath` defaults
- Remove automation steps that trigger cast import
- Update comments to reference PROJECT.md instead

##### `scripts/batch-produciesta.applescript`
- Line 143: `importCastListDirect(customPagesPath)` call
- Line 192-194: `importCastListDirect()` function
- Line 444+: `importCastList()` function

**Action**: Same as above

---

#### 2.4 Shell Scripts

**Files to Update**:

1. `scripts/daily-dao-batch.sh`
2. `scripts/yntswyd-batch.sh`
3. `scripts/meditations-batch.sh`
4. `scripts/produciesta-auto.sh`
5. `scripts/batch-produciesta.sh`

**Action**:
- Search for references to `custom-pages.json`
- Remove any logic that copies/moves these files
- Update to rely on PROJECT.md instead

**Example Pattern to Remove**:
```bash
# Copy custom-pages.json to screenplay directory
cp ~/Documents/custom-pages.json "$screenplay_dir/"
```

---

#### 2.5 Documentation Files

**Files to Update or Archive**:

##### Help System Files (Keep, but update content)
1. `Help/AppleScript/CustomPages.md` - Update to describe PROJECT.md approach
2. `Help/AppleScript/Overview.md` - Remove custom-pages references
3. `Help/AppleScript/Workflows.md` - Update workflows
4. `Help/BatchProcessing/Overview.md` - Line 14: Remove auto-import reference
5. `Help/BatchProcessing/BatchProcessing.md` - Update cast loading documentation
6. `Help/Troubleshooting/AudioGeneration.md` - Line 125: Remove re-import step

##### Planning Documents (Archive)
1. `Docs/old/CAST_LIST_IMPORT_EXPORT_PLAN.md` - Already in `old/`, keep as-is
2. `Docs/old/CAST_LIST_REQUIREMENTS_SUMMARY.md` - Already in `old/`, keep as-is
3. `Docs/old/CLI_CAST_LIST_CHANGES.md` - Already in `old/`, keep as-is
4. `.claude/CAST_TO_PROJECTMD_IMPLEMENTATION.md` - Archive (implementation complete)
5. `.claude/CAST_TO_PROJECTMD_TESTING_PLAN.md` - Archive (implementation complete)
6. `.claude/CAST_REFACTOR_PLAN.md` - Archive (refactor complete)

**New Documentation Needed**:
- **PROJECT.md Cast Management Guide** - How to edit cast in PROJECT.md
- **Migration Guide** - How to convert custom-pages.json to PROJECT.md format

---

### 3. Documentation-Only References

**Files**: These only reference the old approach in documentation/changelogs

1. `SwiftProyecto/CHANGELOG.md` - Historical reference, keep as-is
2. `SwiftProyecto/Docs/PARSE_ARCHITECTURE.md` - May reference old approach, update if needed
3. `Produciesta/CHANGELOG.md` - Historical reference, keep as-is
4. `Produciesta/README.md` - Update if references custom-pages.json
5. `Produciesta/AGENTS.md` - Update if references custom-pages.json

**Action**:
- Review each file
- Update active documentation to reference PROJECT.md approach
- Keep historical changelog entries as-is

---

## Replacement Implementation

### SwiftCompartido Changes

**No replacement needed** - The package should focus on screenplay parsing, not cast management.

**Rationale**:
- SwiftCompartido handles screenplay elements (CHARACTER, DIALOGUE, etc.)
- SwiftProyecto handles project metadata (including cast)
- Separation of concerns: parsing vs. project management

---

### Produciesta Changes

#### Replace Import/Export with PROJECT.md Integration

**Current Flow** (to be removed):
1. User clicks "Import" → opens JSON file
2. Parse `custom-pages.json` → extract `CastListPage`
3. Map to `CharacterVoiceMapping` SwiftData models
4. Save to database

**New Flow** (to implement):
1. **On document open**: Load PROJECT.md via `ProjectMarkdownParser`
2. **Extract cast**: `frontMatter.cast` → array of `CastMember`
3. **Convert to SwiftData**: Map `CastMember` → `CharacterVoiceMapping`
4. **Auto-sync**: When user changes voices in GUI → write back to PROJECT.md

**Implementation**:
- Use `ProjectMdSyncService` (already exists, see `.claude/CAST_TO_PROJECTMD_IMPLEMENTATION.md`)
- Read: `ProjectMarkdownParser().parse(fileURL: projectMdURL)`
- Write: `ProjectMarkdownParser().generate(frontMatter:body:)` → write to disk

**Files to Create**:
- `Produciesta/Services/ProjectMdCastLoader.swift` (if not exists)
- Replace CastingView import logic with PROJECT.md loader

---

## Migration Path for Users

### For Existing Custom-Pages JSON Files

**Option 1: Manual Conversion**
```bash
# Convert custom-pages.json to PROJECT.md cast section
proyecto convert-cast custom-pages.json > cast.yaml
# Then paste into PROJECT.md frontmatter
```

**Option 2: One-Time Import Script**
- Create a migration tool that reads `custom-pages.json`
- Extracts cast members
- Appends to PROJECT.md frontmatter
- Deletes the JSON file

**Option 3: Dual Support (Temporary)**
- Keep read-only support for `custom-pages.json` for 1-2 releases
- Show deprecation warning: "custom-pages.json is deprecated, migrating to PROJECT.md"
- Auto-migrate on first load
- Remove support in future version

---

## Testing Strategy

### Unit Tests to Update

**SwiftCompartido**:
- Remove disabled test files
- Update integration tests to NOT expect custom pages in Highland bundles
- Verify `customPages` property defaults to empty array

**Produciesta**:
- Remove all tests that verify custom-pages.json import/export
- Add tests for PROJECT.md cast loading
- Add tests for GUI → PROJECT.md sync

### Integration Tests

**Test Scenarios**:
1. **New project**: Create PROJECT.md with cast → verify GUI loads correctly
2. **Edit in GUI**: Change voice → verify PROJECT.md updates
3. **Edit PROJECT.md**: Change cast in file → verify GUI reflects changes
4. **Legacy compatibility**: Ensure old Highland files still parse (without custom pages)

---

## Rollout Plan

### Phase 0: SwiftProyecto Foundation (Week 1) ⚠️ MUST COMPLETE FIRST
- [ ] Create `ProjectDiscovery.swift` service
- [ ] Implement `findProjectMd()` with episodes detection
- [ ] Implement `readCast()` with optional provider filtering
- [ ] Add comprehensive unit tests (`ProjectDiscoveryTests.swift`)
  - [ ] Episodes folder detection (all case variations)
  - [ ] Parent directory fallback
  - [ ] Read cast with and without provider filter
  - [ ] Edge cases (no cast, empty PROJECT.md)
- [ ] Add `ProjectMarkdownParser.write()` method
- [ ] Add `ProjectFrontMatter.withCast()` helper
- [ ] Add `ProjectFrontMatter.mergingCast()` helper
- [ ] Update SwiftProyecto AGENTS.md with modification rules and ownership clarification
- [ ] Verify all tests pass (100% coverage on findProjectMd and readCast)
- [ ] Tag SwiftProyecto release (v3.1.0+)

### Phase 1: Preparation (Week 2)
- [ ] Update Produciesta to SwiftProyecto v3.1.0+
- [ ] Review all nominated code
- [ ] Confirm no critical dependencies
- [ ] Create migration guide documentation
- [ ] Write integration tests for PROJECT.md auto-loading

### Phase 2: SwiftCompartido Cleanup (Week 1-3) ⚠️ CAN RUN IN PARALLEL
**Note**: This phase is independent - it can start immediately and run in parallel with Phase 0-1.

- [ ] Delete disabled test files
- [ ] Remove `loadCustomPagesForFile`, `tryLoadCustomPagesJSON`, `writeCustomPagesSidecar`
- [ ] Remove `loadCustomPages` from Highland parser
- [ ] Remove `writeCustomPagesJSON` from TextBundle export
- [ ] Update comments/documentation
- [ ] Run all tests
- [ ] Tag new SwiftCompartido release

### Phase 3: Produciesta Cleanup (Week 4-5)
- [ ] Update ProjectMdSyncService to use `ProjectDiscovery.findProjectMd()`
- [ ] Update to use `ProjectFrontMatter.mergingCast()` for additive export
- [ ] Update to use `ProjectMarkdownParser.write()` for file I/O
- [ ] Remove import/export methods from CastingView
- [ ] **Add TODO markers** for remaining auto-loading issues
- [ ] Remove UI buttons/pickers
- [ ] Remove AppleScript functions
- [ ] Update shell scripts
- [ ] Remove Darwin notifications
- [ ] Update help documentation
- [ ] Test GUI → PROJECT.md sync (verify not broken)
- [ ] **Document known auto-loading issues** for future fix
- [ ] Test automation scripts with new approach

### Phase 4: Documentation & Migration (Week 6)
- [ ] Archive old planning documents
- [ ] Update user-facing help files
- [ ] Create migration guide
- [ ] Update README files
- [ ] Update CHANGELOG with breaking changes
- [ ] Create release notes

### Phase 5: Release (Week 7)
- [ ] Final testing
- [ ] Create GitHub release with migration notes
- [ ] Update package-collection
- [ ] Announce deprecation in community channels

---

## Breaking Changes

### For End Users
- **Import/Export buttons removed** from Produciesta CastingView
- **custom-pages.json files no longer loaded** automatically
- **PROJECT.md is now required** for cast management
- **Migration tool provided** for one-time conversion

### For Developers
- **SwiftCompartido API change**: `customPages` property still exists but is no longer populated from files
- **Highland export**: No longer includes `resources/custom-pages.json`
- **Fountain sidecar**: No longer looks for `{basename}-custom-pages.json`

### For Automation Scripts
- **AppleScript**: Remove `importCastListDirect()` calls
- **Shell scripts**: Remove custom-pages.json copying
- **CI/CD**: Update batch processing to use PROJECT.md

---

## Risks & Mitigation

### Risk 1: Users with existing custom-pages.json files
**Mitigation**:
- Provide migration tool
- Show one-time migration dialog
- Keep read-only support for 1 release cycle

### Risk 2: Highland compatibility
**Mitigation**:
- Keep `CastListPage` model for Highland import (read-only)
- Document that Highland export won't include cast pages
- Recommend PROJECT.md as canonical source

### Risk 3: Breaking automation workflows
**Mitigation**:
- Update example scripts in repository
- Provide migration guide for AppleScript users
- Add warnings in release notes

### Risk 4: Loss of cast data
**Mitigation**:
- Migration tool validates data before conversion
- Backup custom-pages.json before deletion
- Test migration thoroughly

---

## Cast Auto-Loading: Separate Issue (TODO)

**CRITICAL**: Cast auto-loading from PROJECT.md is a **separate concern** from removing custom-pages.json code.

### Current Auto-Loading Triggers

**When cast should load**:
1. **Screenplay import** - Document opened/imported into SwiftData
2. **Voice provider change** - User switches from Apple → ElevenLabs, etc.
3. **PROJECT.md detection** - Look in current folder OR parent folder

### Known Issues with Auto-Loading

**Problem**: Auto-loading has misfired in the past:
- PROJECT.md not found when it exists
- Cast loaded but voices not matched to provider
- Timing issues (SwiftData not ready when load attempted)
- Provider mismatch (loading voices for wrong provider)

**Additional Critical Issues**:

#### Issue A: Episodes Folder Detection
**Problem**: PROJECT.md should be written to parent folder when screenplay is in "episodes" folder
- Current code: Writes to screenplay's directory
- Required behavior: If folder name is "episodes" (case-insensitive) → write to parent folder
- Delegation: Let SwiftProyecto determine folder naming conventions
- Example:
  ```
  /project/episodes/chapter-01.fountain
  /project/PROJECT.md  ← Write here (parent of episodes)
  ```

#### Issue B: Additive Cast Export (NOT Replace)
**Problem**: Current implementation REPLACES entire cast array
- Current code: `cast: castMembers.isEmpty ? nil : castMembers` (line 128 in ProjectMdSyncService.swift)
- This **overwrites** all existing cast members
- **Required behavior**: Merge/add voices for current provider only
- Example:
  ```yaml
  # Existing PROJECT.md:
  cast:
    - character: NARRATOR
      voices:
        apple: com.apple.voice.premium.en-US.Aaron
        elevenlabs: 21m00Tcm4TlvDq8ikWAM  # Keep this

  # User assigns VoxAlta voice in GUI for "apple" provider
  # After export (CORRECT):
  cast:
    - character: NARRATOR
      voices:
        apple: voxalta://narrative-1  # Updated
        elevenlabs: 21m00Tcm4TlvDq8ikWAM  # PRESERVED
  ```

**Critical**: Voices for OTHER providers must be preserved during export

### Code Locations for Auto-Loading (Mark as TODO)

#### Produciesta/Services/ProjectMdSyncService.swift

**Current Status**: Write implemented, read is Phase 2 placeholder

##### Line 78-143: `writeCastToProjectMd()` - **REPLACES INSTEAD OF MERGING**
```swift
// Line 90: Only checks current directory (doesn't handle episodes folder)
let projectDir = sourceFileURL.deletingLastPathComponent()
let projectMdURL = projectDir.appendingPathComponent("PROJECT.md")

// Line 128: REPLACES entire cast array (doesn't preserve other providers)
cast: castMembers.isEmpty ? nil : castMembers,  // ❌ WRONG
```

**Critical Issue**: This overwrites voices for ALL providers
- Current: Replaces entire `cast` array with `castMembers` (filtered to current provider)
- Required: Merge voices for current provider into existing cast members
- Example Problem:
  ```yaml
  # Before (has ElevenLabs voices)
  cast:
    - character: NARRATOR
      voices:
        elevenlabs: 21m00Tcm4TlvDq8ikWAM

  # User assigns Apple voice in GUI
  # After (CURRENT BROKEN BEHAVIOR):
  cast:
    - character: NARRATOR
      voices:
        apple: com.apple.voice.premium.en-US.Aaron  # ElevenLabs voice LOST!
  ```

**TODO**: Implement merge logic (Separate Action)
```swift
// TODO: Replace writeCastToProjectMd() implementation
// 1. Load existing cast from PROJECT.md (frontMatter.cast)
// 2. For each new voice assignment:
//    - Find existing CastMember by character name
//    - If found: Update voices[providerID] = newVoiceURI
//    - If not found: Create new CastMember
//    - Preserve all voices[otherProvider] entries
// 3. Write merged cast back to PROJECT.md
```

##### Line 154-161: `readCastFromProjectMd()` - **NOT IMPLEMENTED**
```swift
func readCastFromProjectMd(
    projectURL: URL,
    providerID: String
) async throws -> [CharacterVoiceMapping] {
    // TODO: Phase 2 - Implement reading from PROJECT.md
    debugLog("📝 [PROJECTMD-SYNC] readCastFromProjectMd called (Phase 2)")
    return []
}
```

**Issues to Fix** (Separate Action):
```swift
// MARK: - Cast Auto-Loading (FIXME - Separate Issue)
//
// Current Implementation Issues:
// 1. readCastFromProjectMd() is not implemented (returns empty array)
// 2. PROJECT.md detection only checks current directory (line 90)
//    - Should check if folder is "episodes" (case-insensitive) → use parent
//    - Should also check parent directory as fallback
//    - Should cache location for session
// 3. No error reporting when PROJECT.md not found
// 4. No validation of voice URIs before loading
// 5. SwiftData timing issues when called from GUI
// 6. writeCastToProjectMd() REPLACES cast instead of MERGING (line 128)
//    - Current: cast: castMembers.isEmpty ? nil : castMembers
//    - Required: Merge voices for current provider, preserve other providers
//
// TODO: Implement robust auto-loading:
//   - Search: episodes parent → current dir → parent dir → error reporting
//   - Parse: ProjectMarkdownParser.parse(fileURL:)
//   - Extract: frontMatter.cast → [CastMember]
//   - Merge: Combine new voices with existing voices per character
//   - Convert: CastMember → CharacterVoiceMapping (with provider filter)
//   - Store: Save to SwiftData via DocumentModelActor
//   - Validate: Check voice URIs are valid for provider
//
// TODO: Implement additive cast export:
//   - Load existing cast from PROJECT.md
//   - For each character in GUI:
//     - Find existing CastMember (by character name)
//     - Update voices[currentProvider] = newVoiceURI
//     - Preserve voices[otherProvider] for all other providers
//   - Write merged cast back to PROJECT.md
//
// See: package-collection/CUSTOM_PAGES_REMOVAL.md § Cast Auto-Loading
```

##### Line 169-173: `projectMdExists()` - PROJECT.md Discovery
```swift
func projectMdExists(for sourceFileURL: URL) -> Bool {
    let projectDir = sourceFileURL.deletingLastPathComponent()
    let projectMdURL = projectDir.appendingPathComponent("PROJECT.md")
    return FileManager.default.fileExists(atPath: projectMdURL.path)
}
```

**Issues**:
- Only checks current directory (where screenplay file is)
- Doesn't check for "episodes" folder (should use parent if in episodes)
- Doesn't check parent directory as fallback
- No caching (repeated file system checks)

**TODO**: Implement `findProjectMd(startingFrom:)` helper with episodes detection
```swift
// TODO: Add helper function (Separate Action)
private func findProjectMd(startingFrom fileURL: URL) -> URL? {
    let currentDir = fileURL.deletingLastPathComponent()
    let folderName = currentDir.lastPathComponent.lowercased()

    // CRITICAL: If in "episodes" folder → use parent directory
    if folderName == "episodes" {
        let parentDir = currentDir.deletingLastPathComponent()
        let parentProjectMd = parentDir.appendingPathComponent("PROJECT.md")

        if FileManager.default.fileExists(atPath: parentProjectMd.path) {
            debugLog("📂 Found PROJECT.md in parent (episodes folder detected)")
            return parentProjectMd
        }
    }

    // Check current directory
    let currentProjectMd = currentDir.appendingPathComponent("PROJECT.md")
    if FileManager.default.fileExists(atPath: currentProjectMd.path) {
        debugLog("📂 Found PROJECT.md in current directory")
        return currentProjectMd
    }

    // Fallback: Check parent directory
    let parentDir = currentDir.deletingLastPathComponent()
    let parentProjectMd = parentDir.appendingPathComponent("PROJECT.md")
    if FileManager.default.fileExists(atPath: parentProjectMd.path) {
        debugLog("📂 Found PROJECT.md in parent directory")
        return parentProjectMd
    }

    debugLog("⚠️ PROJECT.md not found (checked episodes parent, current, parent)")
    return nil
}
```

**Note**: Delegate to SwiftProyecto's `DirectoryContext` for episodes folder detection if available

---

#### Produciesta/Produciesta/CastingView.swift

**Auto-Loading Trigger Points**:

##### Line 271-280: `.task` block - Initial load
```swift
.task { @MainActor in
    // Calculate character data immediately (fast operation)
    updateCharacterData()

    // Setup voice mapping automatically - voices are already preloaded at app launch
    await setupVoiceMapping()

    // Auto-import custom-pages.json if available  ← REMOVE THIS
    await checkAndAutoImportCastList()              ← REMOVE THIS
}
```

**Action**:
- **Remove**: `checkAndAutoImportCastList()` call (custom-pages.json)
- **Keep**: `setupVoiceMapping()` (may call PROJECT.md loading)
- **Add TODO**: Mark PROJECT.md auto-loading issues

##### Line 281-289: `.onChange(of: selectedProviderId)` - Provider change
```swift
.onChange(of: selectedProviderId) { _, _ in
    Task { @MainActor in
        // Reset and reload voice mapping when provider changes
        // Voices are already preloaded, just need to set up the mapping
        voiceMappingManager = nil
        audioGenerationService = nil
        await setupVoiceMapping()  // ← May trigger PROJECT.md reload
    }
}
```

**Issues** (Separate Action):
- Provider change should reload voices from PROJECT.md
- Need to filter cast by new provider
- Need to validate voice URIs for new provider
- SwiftData timing issues on rapid provider switches

**TODO**: Add validation and error handling
```swift
// TODO: Fix provider change auto-loading (Separate Action)
// When provider changes:
// 1. Load cast from PROJECT.md (if exists)
// 2. Filter voices for new provider
// 3. Validate voice URIs before storing
// 4. Handle missing voices gracefully
// 5. Update UI to show which characters have voices for this provider
```

---

#### Future Implementation: `setupVoiceMapping()`

**Location**: Search CastingView.swift for `func setupVoiceMapping()`

**Expected Behavior** (Separate Action):
1. Check if PROJECT.md exists (current or parent directory)
2. If exists: Call `ProjectMdSyncService.readCastFromProjectMd()`
3. Convert `CastMember` → `CharacterVoiceMapping`
4. Save to SwiftData via `DocumentModelActor`
5. Reload UI to reflect loaded voices

**Known Issues to Fix**:
- PROJECT.md not found when it exists (search path issue)
- Voices loaded but not matched to provider (filter issue)
- SwiftData not ready (timing issue)
- No error reporting to user

**Action for this removal plan**:
- **DO**: Remove custom-pages.json auto-import code
- **DON'T**: Try to fix PROJECT.md auto-loading now
- **DO**: Add TODO markers for auto-loading issues
- **DO**: Document current auto-loading behavior

### TODO Markers to Add

```swift
// MARK: - Cast Auto-Loading (FIXME - Separate Issue)
// TODO: Improve PROJECT.md discovery logic
//   - Check current directory first
//   - Then check parent directory
//   - Cache PROJECT.md location for session
//   - Better error reporting when not found
//
// TODO: Fix voice provider matching
//   - Ensure voices loaded for CURRENT provider only
//   - Handle provider switch without full reload
//   - Validate voice URIs before storing
//
// TODO: Fix SwiftData timing issues
//   - Ensure dataActor is ready before loading
//   - Use structured concurrency (not unstructured tasks)
//   - Proper error handling and logging
```

### Separation of Concerns

| Concern | This Removal Plan | Future Auto-Loading Fix |
|---------|-------------------|------------------------|
| **custom-pages.json I/O** | ✅ Remove all code | N/A (deleted) |
| **PROJECT.md discovery** | ⚠️ Mark as TODO | 🔧 Implement robust search |
| **Voice provider matching** | ⚠️ Mark as TODO | 🔧 Fix provider logic |
| **SwiftData timing** | ⚠️ Mark as TODO | 🔧 Fix concurrency |
| **Import/Export UI** | ✅ Remove buttons | N/A (PROJECT.md is automatic) |

### What NOT to Do in This Removal

**❌ Don't attempt to fix**:
- PROJECT.md detection logic
- Voice provider matching algorithm
- SwiftData concurrency issues
- Auto-loading timing/sequencing

**✅ Do ensure**:
- Removing custom-pages code doesn't break existing PROJECT.md loading
- TODO markers are clear and actionable
- Auto-loading triggers are documented
- Future fix is scoped separately

---

## Open Questions

1. **Should we keep read-only support for custom-pages.json temporarily?**
   - Pro: Easier migration for users
   - Con: More code to maintain during transition

2. **Should CastListPage be deprecated or kept for Highland compatibility?**
   - Decision: Keep for now, deprecate in documentation
   - Revisit in future release if Highland support is dropped

3. **Should we auto-migrate on first load or require manual action?**
   - Recommendation: Auto-migrate with confirmation dialog
   - Backup original file before migration

4. **What happens to Highland bundles with custom-pages.json on import?**
   - Recommendation: Read cast list, show migration dialog, save to PROJECT.md

---

## Success Criteria

### SwiftProyecto Foundation (Phase 0) ⚠️ REQUIRED FIRST
- [ ] `ProjectDiscovery.findProjectMd()` implemented and tested
- [ ] Episodes folder detection works (case-insensitive: "episodes", "Episodes", "EPISODES")
- [ ] Parent directory fallback works
- [ ] `ProjectMarkdownParser.write()` method implemented
- [ ] `ProjectFrontMatter.withCast()` helper implemented
- [ ] `ProjectFrontMatter.mergingCast()` helper implemented with provider merging
- [ ] All unit tests pass (100% coverage on findProjectMd scenarios)
- [ ] AGENTS.md documented with PROJECT.md modification rules
- [ ] SwiftProyecto v3.1.0+ tagged and released

### Custom-Pages Removal (Phases 1-5)
- [ ] Zero references to `custom-pages.json` file I/O in active code
- [ ] All import/export methods deleted from CastingView
- [ ] AppleScript automation updated (no custom-pages references)
- [ ] Shell scripts updated (no custom-pages copying)
- [ ] UI buttons/pickers removed
- [ ] Disabled test files deleted
- [ ] Documentation archived or updated
- [ ] All tests pass
- [ ] Migration guide published
- [ ] Release notes include breaking changes

### PROJECT.md Auto-Loading (Separate Action - NOT This Plan)
- [ ] TODO markers added to auto-loading code
- [ ] Existing PROJECT.md loading verified not broken
- [ ] Auto-loading issues documented for future fix
- [ ] Separate GitHub issue created for auto-loading improvements
- [ ] No auto-loading fixes attempted in this removal

### Separation of Concerns Checklist

**When Removing Code, Ask:**
- ❓ Is this custom-pages.json I/O? → **DELETE IT**
- ❓ Is this PROJECT.md auto-loading? → **MARK TODO, DON'T FIX**
- ❓ Will removing this break PROJECT.md loading? → **TEST IT**

**Red Flags (DO NOT Remove)**:
- ❌ `ProjectMarkdownParser` usage
- ❌ `ProjectFrontMatter` models
- ❌ `CastMember` conversion logic (SwiftProyecto → SwiftData)
- ❌ `readCastFromProjectMd()` function (even though it's not implemented)
- ❌ `projectMdExists()` helper
- ❌ `setupVoiceMapping()` calls

**Green Lights (SAFE to Remove)**:
- ✅ `custom-pages.json` file paths
- ✅ `CustomPageContainer` JSON parsing
- ✅ `CastListPage` JSON import/export
- ✅ `checkAndAutoImportCastList()` method
- ✅ `processCastListImport()` method
- ✅ Import/Export buttons in CastingView
- ✅ `automationImportPath` user defaults
- ✅ AppleScript `importCastList()` functions

---

## Related Documents

- [SwiftProyecto README](../SwiftProyecto/README.md) - PROJECT.md specification
- [CastMember Model](../SwiftProyecto/Sources/SwiftProyecto/Models/CastMember.swift) - New cast data model
- [CAST_TO_PROJECTMD_IMPLEMENTATION.md](../Produciesta/.claude/CAST_TO_PROJECTMD_IMPLEMENTATION.md) - Original implementation plan
- [CUSTOM_PAGES_REQUIREMENTS.md](../SwiftCompartido/.claude/docs/CUSTOM_PAGES_REQUIREMENTS.md) - Historical requirements (to be archived)

---

## Requirements Summary for Sprint Supervisor

### Critical Path

This requirements document has **TWO distinct workstreams** that must be executed in order:

#### Workstream 1: SwiftProyecto Foundation (BLOCKING)
**Phase 0 (Week 1)** - Must complete before any custom-pages removal begins

**Deliverables**:
1. `ProjectDiscovery` service with `findProjectMd()`
2. Episodes folder detection (case-insensitive)
3. `ProjectMarkdownParser.write()` method
4. `ProjectFrontMatter` helper methods (withCast, mergingCast)
5. Comprehensive unit tests
6. AGENTS.md documentation
7. SwiftProyecto v3.1.0+ release

**Acceptance Criteria**:
- All tests pass
- Episodes detection verified with unit tests
- Cast merging preserves other providers
- API documented in AGENTS.md

---

#### Workstream 2: Custom-Pages Removal (DEPENDENT)
**Phases 1-5 (Weeks 2-7)** - Can only begin after Phase 0 complete

**Dependencies**:
- SwiftProyecto v3.1.0+ released
- Produciesta updated to use new API
- All integration points tested

**Deliverables**:
1. SwiftCompartido cleanup (remove sidecar JSON code)
2. Produciesta cleanup (remove import/export UI, use SwiftProyecto API)
3. Documentation updates
4. Migration guide
5. Release with breaking changes

---

### Key Integration Points

| Component | Depends On | Action |
|-----------|-----------|--------|
| **SwiftProyecto** | None | Implement foundation (Phase 0) |
| **Produciesta** | SwiftProyecto v3.1.0+ | Update to use new API (Phase 1) |
| **SwiftCompartido** | None | Remove custom-pages code (Phase 2) |
| **Produciesta UI** | SwiftProyecto API | Remove import/export (Phase 3) |

---

### Risk Mitigation

1. **Phase 0 blocks everything** - If SwiftProyecto foundation is incomplete or buggy, all downstream work is blocked
2. **Test coverage is critical** - Episodes detection must work in all cases (case-insensitive, parent fallback)
3. **Cast merging must be additive** - Losing voices for other providers is a data loss bug
4. **Migration path required** - Users with custom-pages.json need conversion tool

---

### Questions for Sprint Planning

1. Should Phase 0 (SwiftProyecto) be a separate sprint from Phases 1-5?
2. Do we need a migration tool or just documentation for converting custom-pages.json?
3. Should we keep read-only support for custom-pages.json temporarily (1 release cycle)?
4. What's the testing strategy for episodes folder detection on case-sensitive filesystems?

---

**Document Version**: 2.0
**Created**: 2026-02-15
**Last Updated**: 2026-02-15
**Author**: Claude (via package-collection audit)
**Status**: Ready for Sprint Supervisor breakdown
