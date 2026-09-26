# AI Log

Running history of AI-assisted work on EcoSteps: what changed, why, and what's still open. Newest entries at the bottom. Read this file in full before starting new work in this repo. When you finish something worth remembering (a fix, a refactor, a decision), append a new entry in the same format — don't edit past entries except to update the "Known issues" list.

Convention: when removing something that's genuinely unused (an asset, a file) rather than actively wrong code, move it into `archive/` instead of deleting it outright — see `archive/README.md`. Dead code *inside* an otherwise-used file (an unused method, an orphaned snippet) should just be deleted; archiving only makes sense for whole files.

---

## 2026-09-26 — iOS deployment target bumped to 15.0

Xcode's current toolchain no longer supports the 13.0 target the project was pinned to, which blocked all iOS Simulator builds. Updated `ios/Podfile`, `ios/Podfile.lock`, and `ios/Runner.xcodeproj/project.pbxproj`, and added a `post_install` hook in the Podfile forcing `IPHONEOS_DEPLOYMENT_TARGET = 15.0` on every CocoaPods target (individual pods were overriding the project-level setting).

Files: `ios/Podfile`, `ios/Podfile.lock`, `ios/Runner.xcodeproj/project.pbxproj`
Commit: 886ba79

## 2026-09-26 — Fixed deleted/renamed challenges resurrecting; safer progress reset

`ChallengeRepository.loadChallenges()` used to re-add any seed challenge missing from the saved file, so deleting or renaming a bubble in Playground silently reverted on the next app launch. Added `seenSeedIds` tracking (persisted alongside the challenge data) so a seed challenge that's already been shown once is never resurrected after the user removes it — only genuinely new seed entries get added automatically. Verified by deleting a challenge at the file level and confirming a full relaunch didn't bring it back.

Also fixed the tree screen's "Reset" button (`start_page.dart`): it used to call `prefs.clear()` with no confirmation, which wiped unrelated Settings toggles while leaving checklist completion untouched (an inconsistent half-reset) and never refreshed the UI. It now shows a confirmation dialog, only clears `progress_*`/`unlocked_nodes` keys, resets checklist completion in the same step, and reloads immediately.

Files: `lib/challenge_repository.dart`, `lib/start_page.dart`
Commit: 19877ff

## 2026-09-26 — Startup Sound setting now respected

`main.dart` had a comment explicitly admitting the Startup Sound toggle was ignored — the sound always played regardless of the switch in Settings. Wired `_playStartupSound()` to read `AppSettingKeys.startupSound` from `SharedPreferences` and skip playback when disabled.

Note: most other Settings toggles (System Sounds, Background Music, Reduce Motion, High Contrast Text, Daily Reminders, Milestone Alerts, Friend Updates, Share Total/Category Progress, Share Checked Items) are still dead UI — they persist a value but nothing in the app reads it back, because the underlying features (sound effects, background music, local notifications, a sharing backend) don't exist yet. Wiring those up is feature work, not a bug fix — flagged here so it isn't mistaken for an oversight.

Files: `lib/main.dart`
Commit: f3b17d8

## 2026-09-26 — Consistent error handling on challenge-data load

`start_page.dart` and `playground.dart` wrapped `loadChallenges()` in try/catch; the HomeScreen (`main.dart`), `profile_page.dart`, and `progress_register_page.dart` didn't — so a corrupted `challenge_editor.json` crashed only some screens. All five now catch load failures the same way and degrade to an empty/loaded state instead of crashing. Verified by writing invalid JSON into the simulator's `challenge_editor.json` and confirming every screen (Home, Start, Progress Register) still rendered instead of showing a red error screen.

Files: `lib/main.dart`, `lib/profile_page.dart`, `lib/progress_register_page.dart`
Commit: e226a54

## 2026-09-26 — Shared ChallengeStore (single source of truth for challenge data)

Home, Start, Playground, Profile, and Progress Register each independently loaded and cached their own copy of the challenge data, so an edit made on one screen (e.g. checking off an item in Progress Register) wasn't reflected on another screen that was already open, until that screen happened to reload on its own.

Added `lib/challenge_store.dart`: a `ChangeNotifier` singleton wrapping `ChallengeRepository`. Every screen now reads via `ChallengeStore.instance.ensureLoaded()`/`.challenges`, writes via `ChallengeStore.instance.save(...)`, and adds itself as a listener so it re-renders the instant any screen saves a change. `start_page.dart`'s listener also re-runs `_syncNodeCompletionFromChecklist` so the tree's completed-bubble highlighting stays correct without rebuilding the node graph/physics state.

Side effect: `ChallengeRepository.loadChallenges()`'s seed-merge-and-rewrite now only runs once per app session (the first screen to touch the store) instead of once per screen — partially addresses the "repository rewrites the file on every read" finding too, though the repository method itself is unchanged.

Verified live on the simulator: toggled a checklist item in Progress Register, then confirmed Home's welcome-card count and Profile's totals updated without navigating away or re-opening either screen.

Files: `lib/challenge_store.dart` (new), `lib/main.dart`, `lib/playground.dart`, `lib/profile_page.dart`, `lib/progress_register_page.dart`, `lib/start_page.dart`
Commit: e1e50f5

## 2026-09-26 — Added AI_LOG.md and CLAUDE.md

This file, and the `CLAUDE.md` that points to it. `CLAUDE.md` is auto-loaded by Claude Code at the start of every session in this repo, so reading this log first is no longer optional-by-convention.

Commit: 68fcdb5

## 2026-09-26 — Real test coverage for ChallengeRepository and ChallengeStore

`test/widget_test.dart` was still the unmodified Flutter counter-app template — it tested a `+` icon that doesn't exist in this app and would have failed if anyone ran `flutter test`. The project had zero real coverage.

Added `test/challenge_repository_test.dart` and `test/challenge_store_test.dart`, using a hand-rolled `_FakePathProviderPlatform` (extends `PathProviderPlatform`, overrides `getApplicationDocumentsPath()`) so tests run against a `Directory.systemTemp` temp dir instead of a real device/simulator. Covers: seeding from the bundled asset, checklist completion surviving a reload, the delete/rename-doesn't-resurrect fix from earlier today, the legacy bare-list save format, and `ChallengeStore`'s cache/reload/notify contract. Replaced the stale counter test in `widget_test.dart` with a real (if minimal) test of `GlassButton`.

Sanity-checked that the new repository tests actually catch the bug: temporarily swapped in the pre-fix `challenge_repository.dart` (via `git show 886ba79:...`), confirmed the two resurrection tests failed with the expected assertion errors, then restored the fix and confirmed all 8 tests passed again.

Added `path_provider_platform_interface` as an explicit dev dependency (was previously only resolvable transitively through `path_provider`) so the fake platform import doesn't silently break if `path_provider`'s dependency graph changes.

Files: `test/challenge_repository_test.dart` (new), `test/challenge_store_test.dart` (new), `test/widget_test.dart`, `pubspec.yaml`, `pubspec.lock`
Commit: 2902680

## 2026-09-26 — Added archive/ for unused-but-not-deleted files

`assets/background3.jpg` was tracked in git but never declared in `pubspec.yaml`'s `assets:` list and never referenced by any `Image.asset()` call — dead weight in the repo. Rather than deleting things like this outright going forward, they go in `archive/` (see `archive/README.md`) in case they were meant for something that never got finished. Moved `background3.jpg` there as the first entry.

Files: `archive/README.md` (new), `archive/assets/background3.jpg` (moved from `assets/`)
Commit: e4e405b

## 2026-09-26 — Removed dead code; consolidated duplicated progress math

`start_page.dart` had a second, orphaned top-level `main()` (leftover from standalone widget testing) that was never the app's real entry point — removed it.

`_totalItems`/`_completedItems`/`_progress` were computed identically in `main.dart`, `profile_page.dart`, and `progress_register_page.dart` (finding #8 from the original review). Moved that logic onto `ChallengeStore` as `totalItems`/`completedItems`/`progress` getters — natural now that all three screens already read through it as their single source of truth — and updated each screen to use them instead of keeping its own copy. `profile_page.dart`'s per-category breakdown (`_categoryProgress`/`_buildCategoryProgress`) was left alone; it's a different, more complex aggregation (recursive per-category totals), not a duplicate of the simple total.

Verified with `flutter analyze` (clean) and `flutter test` (all passing, including a new test for the store getters), then relaunched on the simulator and confirmed Profile still showed the correct totals ("1/118", "Kitchen 1/47") after the refactor.

Files: `lib/challenge_store.dart`, `lib/main.dart`, `lib/profile_page.dart`, `lib/progress_register_page.dart`, `lib/start_page.dart`, `test/challenge_store_test.dart`
Commit: 177de6d

---

## Known issues not yet fixed

From a full-codebase review, roughly ranked by impact. Struck-through items are resolved above.

1. ~~Deleted/renamed challenges resurrect~~ — fixed 2026-09-26.
2. ~~Reset button was destructive/inconsistent~~ — fixed 2026-09-26.
3. Most Settings toggles are dead UI — see note above. Fixing this means building the underlying features (sound effects, music, notifications, sharing), not patching a bug.
4. ~~Inconsistent error handling on data load~~ — fixed 2026-09-26.
5. ~~No single source of truth for progress data~~ — fixed 2026-09-26.
6. `ChallengeRepository.loadChallenges()` still always re-merges and rewrites the save file the first time it's called each session. Mitigated (not eliminated) by the shared store above.
7. ~~`test/widget_test.dart` was still the unmodified Flutter counter-app template; no real test coverage~~ — fixed 2026-09-26 (repository/store unit tests added; UI-level coverage is still thin).
8. ~~Progress-calculation logic duplicated across `main.dart`, `profile_page.dart`, `progress_register_page.dart`~~ — fixed 2026-09-26 (moved onto `ChallengeStore`).
9. The glass/blur panel widget is reimplemented separately in `profile_page.dart`, `friends_page.dart`, and inlined ad hoc elsewhere.
10. `start_page.dart` and `playground.dart` are 1000+ line God files, each mixing physics/layout, CRUD, dialogs, and rendering in one `State` class.
11. Per-frame O(n²) physics simulation in `start_page.dart` runs 60x/sec even at rest, rebuilding several `BackdropFilter`s — will degrade as the tree grows.
12. ~~Dead orphaned `main()` in `start_page.dart`~~ — fixed 2026-09-26.
13. "Thomas Pennock" / "TP" is hardcoded across four files instead of a single user model — will need to change if real accounts are ever added.
