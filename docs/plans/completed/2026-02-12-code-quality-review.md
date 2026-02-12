# Code Quality Review for Public Release

Review and improve code quality for the refactoring branch changes before public release. Focus on test coverage, code consistency, and documentation.

## Context

- **Files involved:**
  - Sources/Managers/SettingsManager.swift
  - Sources/Managers/MenuBarManager.swift
  - Sources/Managers/WindowManager.swift
  - Sources/Managers/NowPlayingController.swift
  - Sources/Protocols/ManagerProtocols.swift
  - Sources/MediaController.swift
  - Tests/SettingsManagerTests.swift (new)
  - Tests/NowPlayingControllerTests.swift (new)
- **Related patterns:** Existing test patterns in ColorsTests.swift, ConfigTests.swift
- **Dependencies:** XCTest framework

## Approach

- **Testing approach:** Regular (code first, then tests for existing code)
- Complete each task fully before moving to the next
- **CRITICAL: every task MUST include new/updated tests**
- **CRITICAL: all tests must pass before starting next task**

---

## Task 1: Add SettingsManager unit tests

**Files:**
- Create: `Tests/SettingsManagerTests.swift`

- [x] Create test struct mirroring SettingsManager behavior (similar to TestConfig pattern)
- [x] Test updateOpacity updates config and notifies delegate
- [x] Test updateBackgroundColor converts NSColor to hex correctly
- [x] Test updateShowInDock notifies delegate
- [x] Test updateShowInMenuBar notifies delegate
- [x] Test updateAlwaysOnTop notifies delegate
- [x] Test updateLastfmEnabled enables/disables scrobble service
- [x] Test updateAdaptiveColors notifies delegate
- [x] Test resetSettings restores defaults and notifies delegate
- [x] Run `swift test` - must pass before task 2

---

## Task 2: Add NowPlayingController tests

**Files:**
- Create: `Tests/NowPlayingControllerTests.swift`

- [x] Create mock delegate for testing
- [x] Test scheduleUpdate calls updateNowPlaying after delay
- [x] Test updateNowPlaying guards against concurrent updates
- [x] Test delegate notification for track info updates
- [x] Test delegate notification for artwork changes
- [x] Test scrobble info tracking on track change
- [x] Run `swift test` - must pass before task 3

---

## Task 3: Fix potential memory leak in NowPlayingController

**Files:**
- Modify: `Sources/Managers/NowPlayingController.swift`

- [x] Ensure timer is invalidated when NowPlayingController is deinitialized (verify deinit implementation)
- [x] Add stopUpdates call to ensure clean teardown
- [x] Run `swift test` - must pass before task 4

---

## Task 4: Improve MediaController thread safety

**Files:**
- Modify: `Sources/MediaController.swift`

- [x] Make currentArtworkRequestId thread-safe using a lock or serial queue
- [x] Verify all cachedArtwork access is on main thread or properly synchronized
- [x] Run `swift test` - must pass before task 5

---

## Task 5: Code style consistency pass

**Files:**
- Modify: `Sources/Managers/MenuBarManager.swift`
- Modify: `Sources/Managers/WindowManager.swift`
- Modify: `Sources/Managers/SettingsManager.swift`

- [x] Ensure consistent MARK comment style across all manager files
- [x] Verify access control modifiers are consistent (private vs internal)
- [x] Remove any redundant self references for consistency
- [x] Run `swift test` - must pass before final validation

---

## Final Validation

- [x] Run `swift test` - all tests must pass
- [x] Verify app builds successfully with `make build`
- [x] Manual test: Launch app and verify basic functionality

## Post-Completion

- [x] Move this plan to `docs/plans/completed/`
