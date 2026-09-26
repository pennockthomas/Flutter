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

## 2026-09-26 — Extracted duplicated GlassPanel widget

`profile_page.dart` and `friends_page.dart` each defined their own private `_GlassPanel` with identical blur/opacity/border styling (`friends_page.dart`'s version just added a `padding` parameter). Moved it to `lib/glass_panel.dart` as a public `GlassPanel` and updated both screens to use it.

Deliberately did *not* touch the other inlined `BackdropFilter` blocks in `settings.dart`, `playground.dart`, and `start_page.dart` — those back circular node bubbles and differently-sized bottom sheets, a visually distinct pattern from the rounded-rectangle info panel, not a duplicate of the same thing. Unifying those would need real design-system thinking, not a straight extraction.

Verified with `flutter analyze`/`flutter test`, and visually on the simulator: Profile and Friends render identically to before.

Files: `lib/glass_panel.dart` (new), `lib/profile_page.dart`, `lib/friends_page.dart`
Commit: 3e471f7

## 2026-09-26 — Decided to defer splitting up the God files

Discussed splitting `start_page.dart`/`playground.dart` (finding #10) into smaller, more testable pieces (e.g. pulling the physics/layout math into a plain `NodeGraphController` class). Thomas's call, which I agreed with: leave it for now. It's a maintainability smell, not a bug, and refactoring the app's most animation-heavy code for a payoff that only matters with frequent future changes there isn't worth the regression risk right now. See the note on item 10 below for when to revisit.

No commit — no code changed.

## 2026-09-26 — Extracted hardcoded user identity into AppUser

"Thomas Pennock"/"TP" were hardcoded as string literals in `main.dart`, `settings.dart`, `profile_page.dart` (×2), and `start_page.dart`, plus a first-name-only "Welcome back, Thomas" greeting in `main.dart` that hadn't been caught by earlier grep passes (it doesn't contain "Pennock" or "TP"). Added `lib/app_user.dart` with `AppUser.name`/`.firstName`/`.initials`, and pointed every call site at it. Unlike #10, this one was basically free — a pure string-constant extraction with no behavior change — so it was worth doing even though the payoff (only matters if a real accounts system gets added) is speculative.

Added `test/app_user_test.dart` for the `firstName`/`initials` derivation logic. Verified with `flutter analyze`/`flutter test` and visually on the simulator (Home's greeting/avatar and Profile's name/avatar render identically).

Files: `lib/app_user.dart` (new), `test/app_user_test.dart` (new), `lib/main.dart`, `lib/settings.dart`, `lib/profile_page.dart`, `lib/start_page.dart`
Commit: 62111e0

## 2026-09-26 — Roadmap agreed; started Phase 1 (making dead Settings toggles real)

Discussed the goal of making the whole app actually function as advertised, not just bug-free. Agreed a roadmap: Phase 0 (cleanup), Phase 1 (local-only features: System Sounds, Background Music, Export/Import, Reduce Motion, High Contrast Text), Phase 2 (local notifications), Phase 3 (real accounts + Friends/Sharing backend - explicitly called out as a much bigger, separate undertaking needing its own go-ahead before starting).

Phase 0 + first Phase 1 item done: added `AppSettings.playSystemSoundIfEnabled()`, which plays the platform's UI click sound via `SystemSound.play()` (no custom audio asset needed) gated on the System Sounds toggle, wired into all three checklist-toggle call sites. Also fixed the stale "Reset Progress: Coming later" Settings label (that feature already exists on the Start screen).

Verified with `flutter analyze`/`flutter test` and on the simulator: toggling a checklist item works with no exceptions.

Files: `lib/app_settings.dart`, `lib/playground.dart`, `lib/progress_register_page.dart`, `lib/settings.dart`, `lib/start_page.dart`
Commit: 6b0a2a9

## 2026-09-26 — Background Music + real sound effects (Phase 1 continued)

Thomas added three audio assets: `assets/sounds/background.wav`, `Finished.wav`, `new unlock.wav`.

Added `lib/background_music.dart` (`BackgroundMusicController`, a singleton so navigating screens doesn't restart/duplicate playback): loops `background.wav`, synced with the Background Music toggle (applies immediately when flipped in Settings via a new `onChanged` callback on `_SettingSwitchTile`, not just on next app launch), and paused/resumed via a `WidgetsBindingObserver` on `HomeScreen` (which stays mounted for the whole session) when the app backgrounds/foregrounds.

Added `Challenge.isFullyCompleted` to the model and used it in all three checklist-toggle call sites (`start_page.dart`, `playground.dart`, `progress_register_page.dart`): play `Finished.wav` instead of the plain system click specifically on the transition from incomplete to fully-complete, otherwise the plain click. `new unlock.wav` plays in `start_page.dart`'s `_spawnNextTier` when a tier is genuinely unlocked (not when restoring previously-unlocked state on app load). Both effects route through a new `AppSettings.playSoundEffectIfEnabled()`, gated on the same System Sounds toggle as the click sound.

Verified with `flutter analyze`/`flutter test`, and live on the simulator: toggling Background Music on/off produced no errors in the logs, and checklist toggling (including a completion transition) fired with no exceptions. Didn't verify the unlock sound audibly on-device — the node-graph canvas's continuous physics drift (see finding #11) made precise repeated tapping there too unreliable to chase further; the code path is identical to the already-verified sound-effect mechanism, just a different trigger point.

Files: `assets/sounds/background.wav` (new), `assets/sounds/Finished.wav` (new), `assets/sounds/new unlock.wav` (new), `lib/background_music.dart` (new), `test/challenge_model_test.dart` (new), `lib/app_settings.dart`, `lib/challenge_model.dart`, `lib/main.dart`, `lib/playground.dart`, `lib/progress_register_page.dart`, `lib/settings.dart`, `lib/start_page.dart`
Commit: 4dca764

## 2026-09-26 — Export/Import Progress and Reduce Motion (Phase 1 continued)

Added `share_plus` and `file_picker` as dependencies. `ChallengeRepository.importFromJson()` validates a JSON string (accepts both the current and legacy save formats, rejects anything else without touching existing data) before writing it as the new save file; `ChallengeStore.importFromJson()`/`.editableFilePath()` wrap that for the UI and reload/notify on success. Settings > Progress & Data now has working "Export Progress" (native iOS share sheet) and "Import Progress" (native document picker) actions.

Hit a real bug while verifying on the simulator: `Share.shareXFiles` kept throwing `PlatformException(sharePositionOrigin: argument must be set...)`. First attempt (`context.findRenderObject()?.localToGlobal(Offset.zero)`) still failed with a *negative* x-offset - because the button lives on `SettingsScreen`, which is the route sitting *underneath* the pushed `SubSettingsPage`, and iOS's parallax back-transition keeps the covered route shifted left (~1/3 screen width) the whole time it's covered, not just mid-animation. Fixed by anchoring the rect at the screen's own local origin (`Rect.fromLTWH(0, 0, width, height)`) instead of trying to compute a global position at all.

Added `AppSettings.reducedMotion` (a `ValueNotifier<bool>`, same pattern as `backgroundDarkness`), loaded at startup and updated live when the Settings toggle flips. Wired it into the two places that actually animate a transition: `start_page.dart`'s camera centering (the zoom/pan when opening or closing a node - the most visible "motion" in the app) now snaps instantly instead of tweening, and `main.dart`'s Home welcome-card slide/resize does the same. Deliberately left `playground.dart` and the continuous physics simulation alone: `playground.dart` has no live animation to gate (its `animateBack()` is dead code, never called), and the physics loop itself is the bigger, separately-flagged risk (see item 11) - not something to fold into this pass.

Verified with `flutter analyze`/`flutter test` (18 tests, all passing, including 4 new `importFromJson` tests) and thoroughly on the simulator: Export Progress produced the real iOS share sheet with a correctly-sized/named file, saving it to Files worked, and Import Progress opened the real document picker without crashing.

Files: `ios/Podfile.lock`, `pubspec.yaml`, `pubspec.lock`, platform-generated plugin registrants (linux/macos/windows), `lib/app_settings.dart`, `lib/challenge_repository.dart`, `lib/challenge_store.dart`, `lib/main.dart`, `lib/settings.dart`, `lib/start_page.dart`, `test/challenge_repository_test.dart`
Commit: b76d4bc

## 2026-09-26 — Removed High Contrast Text setting

Thomas doesn't want it, and it would have needed a real app-wide theme first to do anything real. Removed `AppSettingKeys.highContrastText` and its Settings toggle rather than leaving another dead one. Verified on the simulator: Appearance now just shows Background Brightness, Reduce Motion, and Current Theme.

Files: `lib/app_settings.dart`, `lib/settings.dart`
Commit: 4e6c9c8

## 2026-09-26 — Replaced the default Flutter app icon and home screen title

The app was still shipping the Flutter template's default icon and "Flut" as its home screen name. Set `CFBundleDisplayName` to "EcoSteps" in `ios/Runner/Info.plist`. For the icon, no image-generation tool was available, so it was drawn programmatically with Pillow: a leaf shape (intersection of two offset circles, i.e. a vesica/lens, tilted diagonally with a vein+stem drawn on top) in `Colors.greenAccent`, on the same deep-eco-black background with a soft green glow the splash screen already uses - script and 1024px master kept in the scratchpad, not the repo. Resized to all 15 required iOS sizes via `sips` directly into `Assets.xcassets/AppIcon.appiconset/`, confirmed each is fully opaque (no alpha channel - Apple rejects icons that have one).

iOS only - other platforms (Android/web/macos/etc.) still have the default icon, since iOS is the only platform actually built and tested this session.

Verified on the simulator by pressing the Home button: the home screen now shows the new leaf icon and "EcoSteps" instead of the Flutter logo and "Flut".

Files: `ios/Runner/Info.plist`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` (all 15 regenerated)
Commit: 29539dc

---

## Roadmap status ("make the whole app function as advertised")

Agreed 2026-09-26. Phase 3 (real accounts + Friends/Sharing backend) needs its own explicit go-ahead before starting - it's a different order of magnitude (new backend, auth, privacy decisions), not a line item.

- Phase 0 (cleanup): done.
- Phase 1 (local features): System Sounds ✅, Background Music ✅, Export/Import Progress ✅, Reduce Motion ✅ (camera/transition animations only, not the physics simulation - see item 11). High Contrast Text: **removed instead of built** - Thomas doesn't want it, and it would have needed a real app-wide theme first (colors are hardcoded per-widget across every screen) to do anything real. `AppSettingKeys.highContrastText` and its Settings toggle are gone; don't re-add without asking. Phase 1 is otherwise complete.
- Phase 2 (local notifications - Daily Reminders, Milestone Alerts via `flutter_local_notifications`): not started.
- Phase 3 (real accounts + Friends/Sharing backend): not started, deliberately deferred pending a separate decision.

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
9. ~~Glass/blur panel widget reimplemented separately in `profile_page.dart` and `friends_page.dart`~~ — fixed 2026-09-26 (extracted to `lib/glass_panel.dart`). Other inlined `BackdropFilter` uses elsewhere are a different visual pattern (bubbles/sheets), left alone deliberately.
10. `start_page.dart` and `playground.dart` are 1000+ line God files, each mixing physics/layout, CRUD, dialogs, and rendering in one `State` class. **Deliberately deferred 2026-09-26** (Thomas's call, agreed): this is a maintainability smell, not a bug — it doesn't affect users or cause the kind of failures the other fixes here addressed, and untangling it means touching the riskiest, most animation-heavy code in the app (physics ticker + camera transforms + gestures) for a payoff that only matters if there's frequent future work in these files. Revisit if a specific future change to the node graph starts feeling harder than it should because of file size — don't refactor preemptively.
11. Per-frame O(n²) physics simulation in `start_page.dart` runs 60x/sec even at rest, rebuilding several `BackdropFilter`s — will degrade as the tree grows.
12. ~~Dead orphaned `main()` in `start_page.dart`~~ — fixed 2026-09-26.
13. ~~"Thomas Pennock" / "TP" hardcoded across four files~~ — fixed 2026-09-26 (extracted to `lib/app_user.dart`).
