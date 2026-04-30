---
name: spm-package-audit
description: Audits and automatically fixes Swift Package Manager library packages for Package.resolved git tracking and intrusive-memory dependency patterns. Explicitly invoked only - does not auto-trigger.
---

# SPM Package Audit

Audits Swift Package Manager (SPM) library packages for common configuration issues and automatically applies fixes:

1. **Package.resolved tracking**: Removes from git and adds to .gitignore (libraries should not check this in)
2. **intrusive-memory/* dependency pattern**: Ensures the sibling dependency pattern is used for local development with CI fallback
3. **Version currency**: Updates dependency versions to latest GitHub releases
4. **Helper function validation**: Verifies the sibling pattern helper is correct

This skill is designed for **SPM libraries only** (not GUI apps). It uses a multi-agent approach where each audit runs as a separate pass, then fixes are applied iteratively.

---

## When to Use

Invoke this skill explicitly (by name) when you want to:
- Audit a Swift package for intrusive-memory dependency best practices
- Set up the local/CI sibling dependency pattern
- Clean up Package.resolved from git history
- Update intrusive-memory/* dependencies to latest versions

**Do not use for**: Xcode app projects, non-Swift packages, or packages without intrusive-memory dependencies.

---

## Multi-Agent Workflow

Use the Agent tool to spawn separate passes for each audit type. Do NOT perform audits inline - delegate each to a dedicated agent:

1. **Agent 1**: Package.resolved audit
2. **Agent 2**: Sibling dependency pattern audit
3. **Apply fixes iteratively** based on findings

Each agent should report findings in structured JSON format for easy parsing.

---

## Agent 1: Package.resolved Audit

**Objective**: Determine if Package.resolved is tracked in git and remove it.

**Steps**:
1. Check if Package.resolved exists: `test -f Package.resolved`
2. Check if it's tracked in git: `git ls-files Package.resolved`
3. If tracked, remove it and update .gitignore

**Agent prompt template**:
```
Audit Package.resolved tracking in this SPM package:

1. Check if Package.resolved exists and is tracked in git
2. If tracked, perform:
   - git rm Package.resolved
   - Add "Package.resolved" to .gitignore (create if missing)
   - Commit with message: "chore: Remove Package.resolved from git tracking"

Report findings as JSON:
{
  "package_resolved_tracked": true/false,
  "action_taken": "removed" | "already_clean" | "not_present",
  "gitignore_updated": true/false
}

Working directory: <path>
```

---

## Agent 2: Sibling Dependency Pattern Audit

**Objective**: Ensure intrusive-memory/* dependencies use the sibling pattern with correct versions and helper function.

### Detection Phase

**Steps**:
1. Read Package.swift
2. Identify all intrusive-memory/* dependencies
3. Check if each uses `sibling()` function or direct `.package(url:...)`
4. Validate helper function exists and matches reference implementation
5. For each dependency, fetch latest release from GitHub

**Agent prompt template**:
```
Audit intrusive-memory dependency patterns in Package.swift:

1. Read Package.swift
2. Find all dependencies from github.com/intrusive-memory/*
3. For each dependency:
   - Check if it uses sibling() function or direct .package() call
   - Note current version
   - Fetch latest release: gh api repos/intrusive-memory/<name>/releases/latest -q .tag_name
4. Check if sibling() helper function exists and matches this reference:

```swift
// Reference implementation
import Foundation
import PackageDescription

let useLocalSiblings = ProcessInfo.processInfo.environment["CI"] != "true"

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}
```

Report findings as JSON:
{
  "helper_function_present": true/false,
  "helper_function_correct": true/false,
  "dependencies": [
    {
      "name": "SwiftBruja",
      "current_pattern": "sibling" | "direct",
      "current_version": "1.6.0",
      "latest_version": "1.7.0",
      "needs_update": true
    }
  ]
}

Working directory: <path>
```

### Fix Phase

Based on Agent 2's findings, apply fixes in this order:

#### 1. Add/Fix Helper Function

If `helper_function_present: false` or `helper_function_correct: false`:

1. Check if `import Foundation` is present in Package.swift (needed for ProcessInfo and FileManager)
2. Add it after `// swift-tools-version:` if missing
3. Add or replace the helper function and `useLocalSiblings` variable before the `let package = Package(` declaration

**Example edit**:
```swift
// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
let useLocalSiblings = ProcessInfo.processInfo.environment["CI"] != "true"

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}

let package = Package(
  // ... rest of package definition
```

#### 2. Convert Dependencies to Sibling Pattern

For each dependency with `current_pattern: "direct"`, convert from:
```swift
.package(
  url: "https://github.com/intrusive-memory/SwiftBruja.git", 
  .upToNextMajor(from: "1.6.0")
)
```

To:
```swift
sibling(
  "SwiftBruja",
  remote: "https://github.com/intrusive-memory/SwiftBruja.git",
  from: "1.6.0"
)
```

#### 3. Update Version Numbers

For each dependency with `needs_update: true`, update the version number to `latest_version`.

**Example**:
```swift
sibling(
  "SwiftBruja",
  remote: "https://github.com/intrusive-memory/SwiftBruja.git",
  from: "1.7.0"  // was "1.6.0"
)
```

---

## Applying Fixes

After both agents complete:

1. **Read both JSON reports** to understand what needs fixing
2. **Apply Package.resolved fixes first** (if any)
3. **Apply Package.swift fixes** in order:
   - Add/fix helper function
   - Convert direct dependencies to sibling pattern
   - Update version numbers
4. **Commit changes**:
   ```bash
   git add Package.swift .gitignore
   git commit -m "chore: Apply SPM package audit fixes
   
   - Add sibling dependency pattern for intrusive-memory/* deps
   - Update dependencies to latest versions
   - Remove Package.resolved from git tracking (if applicable)
   
   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
   ```

---

## Summary Report

After completing all fixes, provide a summary:

```markdown
## SPM Package Audit Complete

### Package.resolved
- Status: [removed from git | already clean | not present]
- .gitignore: [updated | already present]

### Sibling Dependency Pattern
- Helper function: [added | fixed | already correct]
- Dependencies audited: X
- Dependencies converted: Y
- Versions updated: Z

### Changed Dependencies
| Dependency | Old Version | New Version | Pattern |
|------------|-------------|-------------|---------|
| SwiftBruja | 1.6.0 | 1.7.0 | sibling |
| SwiftAcervo | 0.8.2 | 0.8.3 | sibling |

### Next Steps
- Review the changes in Package.swift
- Run `xcodebuild build` to verify package resolves correctly
- Push changes to development branch
```

---

## Error Handling

**If not in an SPM package**:
- Check for Package.swift in current directory
- If missing, report: "Not in an SPM package directory. Please navigate to a Swift package and try again."

**If not a library package**:
- Check Package.swift for `.executable` or app-related products
- If detected, warn: "This appears to be an executable/app package. This skill is designed for library packages only. Continue anyway? [Y/n]"

**If no intrusive-memory/* dependencies**:
- Report: "No intrusive-memory dependencies found. Only Package.resolved audit applied."

**If GitHub API fails**:
- Fall back to current version, report: "Could not fetch latest version for <name>, keeping current version."

---

## Notes

- The sibling pattern allows local development with `../SwiftBruja`, `../SwiftAcervo`, etc. while CI always uses pinned GitHub releases
- Package.resolved should NOT be checked in for libraries (but should be for executable packages)
- Version numbers use semantic versioning - the skill updates to latest releases automatically
- The helper function is idempotent - running the audit multiple times won't cause issues
