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

## 2026-09-26 — Rotated the icon's vein 90 degrees; saved the generator into the repo

Thomas's feedback: the vein line was rotated wrong. It was running along the axis connecting the two circles that form the leaf's body; rotated both its endpoints 90 degrees around the leaf's center (verified numerically - the line's direction genuinely flipped from one diagonal to the other, not a no-op) so it now crosses the leaf the other way, and regenerated all 15 icon sizes. Verified again on the simulator via the Home button.

Also moved the icon generator from the session scratchpad into `tool/generate_app_icon.py` (plus its 1024px output, `tool/app_icon_master.png`), since a scratchpad script won't survive to the next session and this is clearly something that'll get tweaked again. Verified the repo copy reproduces the currently-shipped icon byte-for-byte before committing it.

Files: `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` (all 15 regenerated), `tool/generate_app_icon.py` (new), `tool/app_icon_master.png` (new)
Commits: a03543d, 35f9859

## 2026-09-26 — App icon: used the real eco_rounded glyph instead of a hand-drawn leaf

Thomas's feedback: the hand-drawn leaf (two intersecting circles) read as a coffee bean, and asked whether the app icon could just use the same icon shown at startup instead. It can, exactly: found Flutter's own bundled `MaterialIcons-Regular.otf` at `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/`, and looked up `Icons.eco_rounded`'s codepoint (`0xf6f2`) directly in the Flutter SDK source (`packages/flutter/lib/src/material/icons.dart`). Rewrote `tool/generate_app_icon.py` to render that exact glyph via Pillow's `ImageFont.truetype()` on the same background/glow as before, instead of approximating a leaf from primitives. This guarantees the app icon and the in-app splash icon are the literal same shape, not a lookalike.

Also fixed a centering bug: icon fonts' em-square/baseline metrics don't line up with the glyph's actual visual bounds, so `anchor="mm"` alone left it visibly off-center. Now measures the drawn glyph's real bounding box via `textbbox()` first and shifts the draw position so the ink itself - not the font's box - is centered.

Verified on the simulator via the Home button: unmistakably a leaf now, matching the splash screen precisely.

Files: `tool/generate_app_icon.py`, `tool/app_icon_master.png`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` (all 15 regenerated)
Commit: 43af338

## 2026-09-26 — Shifted the icon's leaf 5% down

Thomas asked to preview a 5%-down shift before applying it - rendered a one-off preview (not touching the shipped assets) and sent it over first. Once approved, added a `VERTICAL_SHIFT` constant to `tool/generate_app_icon.py` (applied after the existing true-ink centering) rather than hacking the offset in one-off, so nudging it again later is a one-line change. Verified on the simulator via the Home button.

Files: `tool/generate_app_icon.py`, `tool/app_icon_master.png`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` (all 15 regenerated)
Commit: d438a75

## 2026-09-26 — Phase 2: local notifications (Daily Reminders, Milestone Alerts)

Added `flutter_local_notifications` + `timezone` + `flutter_timezone`. New `lib/notifications.dart` wraps the plugin: `syncDailyReminders()` reads the Daily Reminders setting, requests permission if needed, and schedules/cancels a daily repeating reminder at a fixed time (6pm - there's no UI yet to let the user pick a time; called at startup and whenever the Settings toggle changes). `showMilestoneAlert()` shows a one-off notification gated on the Milestone Alerts setting, wired into the same "challenge checklist just became fully complete" transition already used for the `Finished.wav` sound (all three sites: `start_page.dart`, `playground.dart`, `progress_register_page.dart`).

Verified the permission flow works: the real iOS system dialog appeared automatically on first launch and was granted with no exceptions logged.

Hit a scary startup hang partway through (white screen, stuck right after the native Xcode build step, before any Dart-side log line) that reproduced across several rebuilds - including one with the new `syncDailyReminders()` call at startup temporarily commented out, which ruled out my Dart code as the cause (an un-awaited fire-and-forget Future can't block the first frame anyway; a hang before any engine log line points at native startup). Turned out to be a stuck simulator process, unrelated to this change: `xcrun simctl shutdown`/`boot` on the device fixed it immediately, and the app now launches cleanly every time with the real code restored. Worth remembering: if a similar "stuck right after the native build, nothing in the log" hang shows up again, try a simulator reboot before assuming it's a code bug - this is at least the second time this exact session has hit that failure mode (see the earlier "Lost connection to device" notes) without any actual bug being at fault.

Not yet done: no UI to customize the daily reminder's time (hardcoded 6pm), and Milestone Alerts only fires on "finished a whole challenge" - no alerts yet for other milestones (e.g. round-number total-progress thresholds).

Files: `lib/notifications.dart` (new), `lib/main.dart`, `lib/settings.dart`, `lib/start_page.dart`, `lib/playground.dart`, `lib/progress_register_page.dart`, `pubspec.yaml`, `pubspec.lock`, `ios/Podfile.lock`, `macos/Flutter/GeneratedPluginRegistrant.swift`
Commit: 6cc1f41

---

## 2026-09-26 — Debug option for testing daily reminder delivery

Added `--dart-define=TEST_DAILY_REMINDER=true`: in debug builds, the existing daily reminder schedules two minutes from the scheduling call, using the same notification ID, repeating trigger, permission flow, and cancellation path. Normal builds retain 6pm, and release builds ignore the flag. Restarting the test build or toggling reminders off/on schedules a fresh two-minute test. Run without the flag afterward with reminders enabled to replace the test's repeating schedule with 6pm (or switch reminders off to cancel it).

Built and launched on the iPhone 17 Pro simulator; the scheduling call completed and logged 20:13:36 Amsterdam time. `flutter analyze lib/notifications.dart` and `git diff --check` passed. Banner delivery and cancellation have not yet been visually verified: Simulator was unavailable through the UI tools, so Thomas was asked to press Home and observe delivery.

Files: `lib/notifications.dart`, `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — Daily reminder delivery confirmed

Thomas confirmed the two-minute reminder worked and supplied a screenshot showing the EcoSteps notification with the expected reminder text on the simulator Home screen. This verifies actual background delivery, beyond the earlier successful scheduling call. Cancellation and next-day repetition remain unverified. Relaunched without `TEST_DAILY_REMINDER` to return to the normal 6pm scheduling path; the debug test option remains available for future checks.

Files: `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — Consolidated remaining work in TODO.md

Created a prioritized checklist covering the completeness review, data protection, honest feature presentation, tree performance, notifications, usability, verification, and the deferred social/backend roadmap. Distinguished confirmed reminder delivery from outstanding cancellation/repetition checks and preserved the decisions to defer broad file splitting and remove High Contrast Text. Additional hardening items are proposed work rather than claims of reproduced bugs.

Files: `TODO.md` (new), `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — Honest social preview and safer progress imports

Started the prioritized work in `TODO.md`. Friends now identifies itself as a preview containing sample profiles, and Settings replaces the inactive sharing/Friend Updates toggles with accurate local-only status text. Cloud Sync, Authentication, and Private Items likewise describe current behavior instead of implying an active or imminent service. Removed the now-unused preference keys for those inactive switches.

Progress import now explains that it will replace challenge/checklist progress and requires confirmation. Before a valid import replaces the save, the repository atomically creates one pre-import backup. Settings exposes a confirmed "Restore Pre-Import Backup" action. Normal challenge saves and imports now write to a flushed temporary file and rename it into place, reducing the risk of a partially-written save. `ChallengeStore.save()` also waits for persistence to succeed before changing the shared in-memory state.

Imports are now validated before the confirmation is shown: challenge IDs must be unique and non-empty, `Start` must exist, every unlock must resolve exactly once, and unlock relationships cannot contain a cycle. Added repository coverage for backup availability, restoring completed progress, duplicate IDs, missing references, and cycles. All 23 tests pass. Full `flutter analyze` reports 64 existing info-level deprecation/style notices under the current Flutter SDK and no errors or warnings; those notices were outside this focused change.

Files: `lib/app_settings.dart`, `lib/challenge_repository.dart`, `lib/challenge_store.dart`, `lib/friends_page.dart`, `lib/settings.dart`, `test/challenge_repository_test.dart`, `TODO.md`, `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — Soft, context-aware fades on every vertical scroll area

The rectangular viewport edge visibly sliced through glass cards and checklist rows while scrolling. Added `FadingEdgeScrollView`, which listens to scroll metrics and applies a transparent shader only where more content exists: bottom-only at the start, both edges while between the ends, top-only at the bottom, and no fade when the content fits. Applied it to all nine vertical scrolling areas across Settings and its subpages, Profile, both Friends screens, Progress Register, the checklist screen, Playground editor sheets, and expanded tree-node content.

Verified with `flutter analyze --no-fatal-infos` (no errors or warnings; the same 64 existing info-level notices) and `flutter test` (all 23 tests pass). Visual tuning on the simulator is pending Thomas's review after relaunch.

Files: `lib/fading_edge_scroll_view.dart` (new), `lib/settings.dart`, `lib/profile_page.dart`, `lib/progress_register_page.dart`, `lib/friends_page.dart`, `lib/playground.dart`, `lib/start_page.dart`, `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — Calmer shared page transition

Replaced the platform's full-width slide for in-app navigation with one shared EcoSteps route: a 320ms ease-out cross-fade with a very small upward drift, and a quicker 240ms reverse when going back. The transition is used for every Home destination, Settings subpage, Friends/profile drill-down, and challenge checklist. Reduce Motion still makes these transitions instantaneous. The startup-to-Home fade remains intentionally separate.

Verified with `flutter analyze --no-fatal-infos` (no errors or warnings; the same 64 existing info-level notices) and `flutter test` (all 23 tests pass). Visual tuning is pending Thomas's simulator review.

Files: `lib/app_page_route.dart` (new), `lib/main.dart`, `lib/settings.dart`, `lib/profile_page.dart`, `lib/friends_page.dart`, `lib/start_page.dart`, `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — Tree checklist consolidated into one glass panel

The challenge checklist screen previously rendered each task as its own clipped blur tile, leaving the list visually fragmented over the forest background. Replaced those per-row glass tiles with one large rounded `GlassPanel` filling the checklist area. Tasks now sit inside it on transparent rows with faint inset dividers, while the scroll-edge fade affects only the task content and leaves the outer panel stable.

Verified with `flutter analyze --no-fatal-infos` (no errors or warnings; 62 existing info-level notices) and `flutter test` (all 23 tests pass).

Files: `lib/start_page.dart`, `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — QuickSwipe first usable version

Added a QuickSwipe entry on Home and a new card-based review screen for every eco swap. Swiping right, or tapping the green button, marks the current swap complete; swiping left, or tapping the orange button, marks it still to do. Each decision is saved through the shared `ChallengeStore`, so checklist, progress, and profile views update from the same data. The card shows its category, current status, directional feedback while dragging, a preview of the next card, and a completion summary with a Review Again action.

This first version intentionally uses the complete ordered swap list. Filters, shuffle, undo, streaks, and milestone-specific behavior can be added after the interaction has been reviewed.

Verified with focused `flutter analyze` (no issues), `git diff --check`, and the full test suite (all 23 tests pass).

Files: `lib/quick_swipe_page.dart` (new), `lib/main.dart`, `AI_LOG.md`
Commit: 19ee8aa

---

## 2026-09-26 — QuickSwipe stacked, denser cards

Changed the single-card presentation into a visible pile: up to three upcoming swaps sit behind the active card with alternating rotations, small vertical offsets, and gradually reduced scale and opacity. QuickSwipe now uses its own intentionally dense glass surface with a hard-coded dark fill, stronger blur, larger corner radius, and clearer border so overlapping cards and their text remain legible over the forest background.

Verified with focused `flutter analyze` (no issues), `git diff --check`, and the full test suite (all 23 tests pass).

Files: `lib/quick_swipe_page.dart`, `AI_LOG.md`
Commit: 19ee8aa

## 2026-09-27 — First real product illustration, wired into QuickSwipe

Started on per-product artwork for checklist items (user wants simple illustrations for the ~118 products eventually). Drew a flat "stainless steel lunch box" icon with `tool/generate_product_icons.py` (Pillow, same drawn-not-photographed approach as the app icon) and added `assets/products/metal_lunchbox.png`. `quick_swipe_page.dart` now has a `_productIllustrations` map (checklist label → asset path) and a `_ProductGlyph` widget that shows the matched artwork or falls back to the generic eco glyph — so this can be filled in gradually, one label at a time, without needing all items illustrated at once. First (only) entry maps the real checklist label `"Stainless steel lunch box"` (under Kitchen → Food Storage).

Files: `tool/generate_product_icons.py`, `assets/products/metal_lunchbox.png`, `lib/quick_swipe_page.dart`, `pubspec.yaml`, `AI_LOG.md`
Commit: (pending)

---

## Roadmap ("make the whole app function as advertised, not just bug-free")

Agreed 2026-09-26, after the initial bug-fix/code-quality pass was done. The goal shifted from "fix what's broken" to "make every Settings toggle and advertised feature actually do something real." Full original plan, with current status:

**Phase 0 — Cleanup (~15 min).** Fix any stale "Coming later" labels for features that already secretly exist. ✅ Done (the Reset Progress label).

**Phase 1 — Local-only features, no backend needed.** Each independent, originally estimated 1–5 hrs apiece:
- System Sounds ✅ — `SystemSound.play()`, no custom asset needed.
- Background Music ✅ — loops `assets/sounds/background.wav` via a singleton controller, synced to Settings + app lifecycle.
- Export/Import Progress ✅ — native share sheet / document picker, `ChallengeRepository.importFromJson()` validates before writing.
- Reduce Motion ✅ — camera zoom/pan and the Home welcome-card transition snap instantly when enabled; the continuous physics simulation itself is untouched (see known issue 11).
- High Contrast Text — **removed instead of built.** Thomas doesn't want it, and it would have needed a real app-wide theme first (colors are hardcoded per-widget across every screen) to do anything real. `AppSettingKeys.highContrastText` and its toggle are gone from Settings; don't re-add without asking.
- Phase 1 is complete.

**Phase 2 — Local notifications (~4–6 hrs).** Daily Reminders + Milestone Alerts via `flutter_local_notifications`. ✅ Done - permission flow, daily scheduling, and milestone alerts on challenge completion. Not customizable yet (fixed 6pm reminder time, milestones only fire on "finished a whole challenge") but functionally complete.

**Phase 3 — Real accounts + Friends/Sharing backend (3–5 days, a different order of magnitude).** Choosing a backend (Firebase/Supabase is the fast path), building sign-up/sign-in, a real data model for friends + shared progress, an add-friend/invite flow, replacing the 3 hardcoded mock friends in `friends_page.dart`, and wiring the three "Share X Progress" toggles to something real. Cloud Sync (Privacy & Security) piggybacks on the same backend. **Not started - needs its own explicit go-ahead before starting, since it changes the app from "local personal tool" to "has a backend and other people's data" (hosting, privacy, cost).**

### Phase 3 scoping (2026-09-27)

Decided: **Firebase** (Firestore + Firebase Auth via FlutterFire) — fastest to stand up solo, generous free tier for a small friend group, real-time listeners fit "see a friend's progress update" naturally. Auth: **Sign in with Apple + email/password** fallback.

Breaking Phase 3 into independently-shippable sub-phases so it isn't all-or-nothing:

- **3a. Auth (~0.5–1 day).** Add `firebase_core` + `firebase_auth`, `GoogleService-Info.plist`/Firebase iOS config, Sign in with Apple entitlement, a sign-in/sign-up screen, session persistence. App still works fully offline/local if not signed in — accounts are additive, not required to use the checklist.
- **3b. Cloud sync of own progress (~0.5 day).** On every `ChallengeStore.save()`, also write a lightweight summary (`totalItems`, `completedItems`, per-category counts) to `users/{uid}/progress`. Local JSON file stays the source of truth on-device; Firestore is a mirror for friends to read, not a replacement data layer.
- **3c. Friend graph (~1 day).** Each account gets a short generated `friendCode` (e.g. 6 chars) shown in Profile. Adding a friend = entering their code → write a `friendRequests` doc → they accept/reject → `users/{uid}/friends/{friendUid}` on both sides. No email/SMS/push infra needed for MVP.
- **3d. Real friend screens (~0.5 day).** `friends_page.dart` reads the signed-in user's friend list + each friend's progress doc from Firestore instead of the hardcoded `_friends` list — same UI, real data.
- **3e. Wire sharing/privacy toggles (~0.5 day).** The existing "Share Total/Category/Checked-Items Progress" intent (currently just static "Not connected" info rows in Settings) becomes real toggles that gate exactly what gets written to the shared progress doc.
- **Stretch, not in the estimate:** push notifications for friend requests/milestones — needs APNs setup, treat as a later addition once 3a–3e are stable.

Total: ~3–4 days, in line with the original estimate. Data lives in Firestore under `users/{uid}` (profile + friendCode), `users/{uid}/progress` (synced summary), `users/{uid}/friends/{friendUid}` (accepted), `friendRequests/{id}` (pending). Security rules restrict a progress doc to being readable only by accepted friends + the owner.

Rough total if everything gets built: ~1–2 days for Phases 0–2 (now mostly spent), plus 3–5 days for Phase 3 if it happens.

---

## 2026-09-27 — QuickSwipe: removed redundant direction-hint row

The row of "✕ Still to do / ✓ Already done" labels above the card deck duplicated the decision buttons already shown at the bottom of the screen. Removed the row (and the now-unused `_DirectionHint` widget) — the bottom buttons and the in-card drag stamps already communicate the same thing.

Files: `lib/quick_swipe_page.dart`

## 2026-09-27 — Phase 3a: Firebase Auth (Sign in with Apple + email/password)

First slice of Phase 3 built and verified booting on the simulator (build succeeds, no crash, `flutter analyze` clean).

- Created a Firebase project (`ecosteps-d60b6`) via the console, registered the iOS app under the existing bundle ID `com.thomaspennock.ecosteps`, downloaded `GoogleService-Info.plist` into `ios/Runner/`.
- Installed `flutterfire_cli` and `firebase-tools` locally (no `sudo` — used `dart pub global activate` and an npm user-prefix install; the system Ruby was too old to build the `xcodeproj` gem `flutterfire configure` needs, so installed that gem against Homebrew's Ruby instead). Ran `flutterfire configure --project=ecosteps-d60b6 --platforms=ios`, which generated `lib/firebase_options.dart` and wired `GoogleService-Info.plist` into the Xcode project's Resources build phase automatically.
- Added `firebase_core`, `firebase_auth`, `sign_in_with_apple`, `crypto` to `pubspec.yaml`; ran `pod install`.
- `main.dart`: `main()` is now `async`, calls `Firebase.initializeApp()` before `runApp()`. Wrapped in try/catch — if Firebase can't be reached, the app logs and continues in local-only mode rather than crashing. Accounts are additive, never required.
- Added `ios/Runner/Runner.entitlements` (`com.apple.developer.applesignin`) and wired `CODE_SIGN_ENTITLEMENTS` into all three Runner build configs in `project.pbxproj`. Still needs the matching capability enabled on the App ID in the Apple Developer portal for Sign in with Apple to work outside the Simulator (Thomas to do — account/portal access, not something I can do).
- `lib/auth_service.dart` (new): singleton wrapping `FirebaseAuth` — email/password sign-in & registration, password reset, Sign in with Apple (nonce-based, verified through Firebase), and a `messageFor()` helper that turns `FirebaseAuthException`/Apple errors into short user-facing strings.
- `lib/sign_in_page.dart` (new): sign-in/create-account screen matching the app's existing glass-panel style — native Apple button, divider, email/password form with a sign-in/register toggle. Closing it without signing in changes nothing.
- `lib/profile_page.dart`: added an Account card at the top (`StreamBuilder<User?>` on `authStateChanges`) showing "Not signed in" + a Sign In button, or the signed-in email/name + Sign Out.

Known limitation: Sign in with Apple in the iOS Simulator needs a signed-in (test) Apple ID on the Simulator itself and can be flaky there regardless — email/password is the reliable path to test end-to-end pre-device.

Not done yet (later sub-phases, see Phase 3 scoping above): 3b (cloud sync of progress), 3c (friend graph), 3d (real friend screens), 3e (wire sharing toggles).

Files: `lib/main.dart`, `lib/auth_service.dart`, `lib/sign_in_page.dart`, `lib/profile_page.dart`, `lib/firebase_options.dart`, `ios/Runner/GoogleService-Info.plist`, `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj`, `firebase.json`, `pubspec.yaml`

## 2026-09-27 — Sign In button styling; found and fixed why glass panels blurred inconsistently

Two small follow-ups from testing Phase 3a, then one real bug found by Thomas eyeballing screenshots side by side.

**Sign In button** (Profile's Account card): added 12px of spacing before it and switched it to a white background / dark text per feedback — it was sitting flush against the text next to it and used the default (purple) `FilledButton` theme color.

**Glass panel inconsistency — root cause found.** Thomas noticed some glass panels (Profile, Friends, Settings, Progress Register) looked distinctly more see-through than others (the Start-menu buttons, the expanded node card, the "Local Profile" sub-page, the checklist header). Several rounds of tuning opacity/blur/darkness numbers on the affected panels didn't fix it — because the numbers were never actually the problem. The real cause: **`FadingEdgeScrollView`** (the shared scroll-edge-fade widget, used on every list-based screen) wrapped its child in a `ShaderMask`. A `ShaderMask` forces its child onto its own isolated offscreen compositing layer — so any `BackdropFilter` living *inside* that child (i.e. every glass panel inside a scrolling list) could only blur that isolated, nearly-blank layer instead of the real background photo painted behind it as an earlier sibling. Panels that happened to sit outside a `FadingEdgeScrollView`'s child (the Start-menu buttons, the expanded tree node, the sub-settings page — which wraps the fade *inside* its own already-blurred panel rather than the other way around) were never affected, which is exactly the pattern Thomas spotted by comparing screenshots.

Fixed by rewriting `fading_edge_scroll_view.dart` to render the edge fade as a plain gradient overlay drawn *on top of* the scroll content instead of a `ShaderMask` wrapping it — same visual fade, no compositing isolation. No panel's own blur/opacity values needed to change from their original settings once this was fixed (confirmed by diffing back to nearly their pre-session values). Also restored `AppBackgroundOverlay(fallbackDarkness: 0.32)` on Profile/Friends/Progress Register (briefly tried matching the Start menu's lighter `0.2` while chasing the wrong cause — 0.32 is correct, matching the other detail screens like the checklist view).

Lesson for future glass-panel work: if a panel still looks off, check whether it's a descendant of `FadingEdgeScrollView` (or any other `ShaderMask`/`Opacity`/`ColorFiltered` ancestor) before touching its own blur/color values.

Files: `lib/fading_edge_scroll_view.dart`, `lib/profile_page.dart`, `lib/friends_page.dart`, `lib/progress_register_page.dart`, `lib/settings.dart`

## 2026-09-27 — QuickSwipe: card rotation, shuffle button, and a shuffle animation

Three follow-up rounds on QuickSwipe's card deck, the last two from Thomas reviewing a screen recording rather than a description.

**Round 1 — added a shuffle button and tried to fix a rotation "pop."** The stacked preview cards (depth 1–3) were already tilted, but the promoted card reset to perfectly straight rotation the instant it became active, which read as a jarring snap. First attempt: made the active card's rest angle a single fixed constant (matching depth-1's angle). Also added the shuffle icon button in the header, reordering `_items` from `_currentIndex` onward.

**Round 2 — that "fix" just moved the problem.** Thomas caught it on a screen recording: every card now rotated to the *exact same* angle once active (no variety), and position/scale still jumped instantly on promotion — rotation wasn't the only thing that changes when a card moves from stack to front. Root cause of the "teleport": the promoted card's translate offset and scale changed discretely between the `_StackedPreviewCard` code path and the active-card code path, with nothing animating between them.

Real fix: gave each card slot a **persistent per-position tilt** (`_itemWobble`, a small repeating pattern keyed to index — index 0 always straight, everything else cycles through a fixed set of small angles) used identically whether the card is a stacked preview or the active card, so a promoted card's rotation literally never changes (zero-jump by construction, not by coincidence). Separately, wrapped the active card in a ~200ms "settle" animation that eases its position/scale/opacity from exactly the depth-1 preview's values up to the true active values, instead of snapping — that's what actually killed the teleport.

**Round 3 — a real shuffle animation.** The shuffle button reordered cards instantly with no animation. Added an `AnimationController`-driven flourish: tapping shuffle fans the up-to-4 visible cards out into a hand-of-cards spread (`_buildShuffleAnimation`, a separate non-interactive render path used only while `_isShuffling`), swaps `_items` at the peak of the fan, then eases back into the normal stack with the new order. Dragging and the decision buttons are disabled for the ~0.5s duration so it can't be interrupted mid-shuffle.

Files: `lib/quick_swipe_page.dart`

## 2026-09-27 — Sign in with Apple disabled for now; first install on Thomas's iPhone

Installing on a physical iPhone failed: Thomas's Apple ID is on a free Personal Team, and Apple doesn't allow the Sign in with Apple capability on free teams at all (not a portal setting — a platform restriction; the Simulator doesn't enforce it, which is why it worked there). Thomas chose to hide it behind a flag rather than archive the code:

- `SignInPage.appleSignInAvailable = false` hides the Apple button and its "or" divider. `AuthService.signInWithApple()` and `Runner.entitlements` are untouched.
- Removed `CODE_SIGN_ENTITLEMENTS` from the three Runner build configs in `project.pbxproj` — this is what actually unblocks the device build; the flag only hides the UI.
- **To re-enable** once on a paid Apple Developer Program membership: flip the flag to `true` and re-add `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` to the three Runner configs.

Device install notes: a `flutter run` debug build dies when the cable is unplugged (the debugger session owns the process) — use `flutter run --release -d <device>` for a build that runs standalone. The debug build's "could not access the local network" warning is macOS Local Network permission for the terminal, only needed for hot reload on-device.

Files: `lib/sign_in_page.dart`, `ios/Runner.xcodeproj/project.pbxproj`

## 2026-09-27 — Phase 3b: progress summary synced to Firestore

While signed in, a summary of local progress is mirrored to `users/{uid}/progress/summary` (plus `displayName` on `users/{uid}`). The local JSON file stays the source of truth — this is a one-way copy for friends to read later, never read back.

- `lib/progress_summary.dart` (new, pure, tested): `progressByArea()` (per top-level area, walking the unlock tree with a cycle guard) and `buildProgressSummary()` (completed/total + areas). **Counts only, no item names** — sharing checked items waits for the 3e privacy toggle. Profile's "Progress By Area" now uses `progressByArea()` instead of its own duplicate tree walk.
- `lib/progress_sync.dart` (new): listens to `ChallengeStore` and auth state; debounces writes by 2s, skips writes when the summary is unchanged, uploads immediately on sign-in. Started from `main()` only if `Firebase.initializeApp()` succeeded. Offline writes are queued by the Firestore SDK.
- `firestore.rules` (new, deployed; `firebase.json` points at it): owner-only read/write on `users/{uid}` and its `progress` subcollection, everything else denied. Friends' read access comes with 3c/3d.
- Added `cloud_firestore`.

**Database region:** the first `firebase deploy --only firestore:rules` auto-created the database in `nam5` (US) while enabling the Firestore API — unexpected. Thomas chose europe-west4 (Netherlands); he deleted the empty database himself (my delete attempt was blocked by the permission classifier, correctly), and it was recreated in **europe-west4** with rules redeployed. Lesson: create the database with an explicit `--location` *before* the first rules deploy.

**Simulator:** Xcode updated to 27 and the iOS 26.4 runtime is gone, so the old iPhone 17 Pro simulator can't boot. Now using **iPhone 18 Pro (iOS 27.0), UDID `5420B103-7DF6-4E3A-B075-972A932C99FF`**.

**Not yet verified end-to-end:** the app builds and runs with sync enabled, but no real write has been confirmed — that needs a signed-in account (Thomas to create one on the simulator, then check Firestore → Data in the console).

**Known issue introduced:** for email accounts without a display name, `ProgressSync` falls back to `AppUser.name` ("Thomas Pennock"), so any other user would upload Thomas's name. Must be fixed (display name at sign-up) before friends (3c) — tracked in `TODO.md`.

Tests: 5 new (`test/progress_summary_test.dart`), 28 total, all passing.

Files: `lib/progress_summary.dart`, `lib/progress_sync.dart`, `lib/profile_page.dart`, `lib/main.dart`, `firestore.rules`, `firebase.json`, `pubspec.yaml`, `test/progress_summary_test.dart`
Commit: d9eec07

## 2026-09-27 — Fresh-eyes review; first-run intro, trimmed Settings, Playground behind debug

Thomas asked for a review of the app "from a blank mind." Findings went into `TODO.md` → "P2 — First-run clarity and product polish" (existing overlapping items were updated in place; the stale P3 accounts section was brought up to date). Three were then implemented:

- **Settings: removed every read-only info row** (Thomas: "just remove them"). Local Profile, Friends Preview, Privacy & Security, and Help & Support contained nothing else and are gone; also removed "Current Theme", "Storage", "Developer Editor", "Friend Updates", and the "Reset Progress: Available in Start" pointer. Settings now holds only Appearance, Progress & Data, Sounds, Notifications (+ Developer in debug). `_infoTile` deleted.
- **Playground off the Home menu.** It can rename/delete challenges, so it's a developer tool: now only under Settings → Developer, a section that exists only when `kDebugMode`. Release builds (incl. Thomas's phone) have no Playground. QuickSwipe's empty-state text no longer mentions it.
- **First-run intro** (`lib/intro_page.dart`): 3 glass-panel slides (what the app is / the tree / tick off what you already own) between the splash and Home, first launch only (pref `onboarding.intro_seen`), with Skip, page dots, reduced-motion aware. Startup captures the `NavigatorState` up front because the splash's context is gone by the time the intro finishes. Replay via Settings → Developer (debug). Plus a "Tap Start to begin" hint under the lone Start bubble until it's opened. No Home tagline — the splash already says "One step closer to plastic-free".

Tests: 3 new (`test/intro_page_test.dart`), 31 total, all passing.

Files: `lib/intro_page.dart`, `lib/main.dart`, `lib/settings.dart`, `lib/start_page.dart`, `lib/quick_swipe_page.dart`, `lib/app_settings.dart`, `test/intro_page_test.dart`, `TODO.md`
Commit: f689668

## 2026-09-27 — Fixed overlapping saves colliding on the shared `.tmp` file

Surfaced by the tab restructure (next entry): three tabs plus their profile avatars all called `ChallengeStore.ensureLoaded()` at the same moment. Each load can rewrite the save file (known issue 6), and every write goes through the same `challenge_editor.json.tmp` before being renamed into place, so overlapping writes renamed that file out from under each other → `PathNotFoundException` at startup.

Fix in `ChallengeStore`: every disk operation (`reload`, `save`, `importFromJson`, `restoreImportBackup`) runs through a single queue (`_serialized`), so only one touches the file at a time; `ensureLoaded` shares one in-flight initial load instead of starting several (and doesn't cache a failed load). Import/restore reload via the unqueued `_reloadNow` to avoid queueing behind themselves. Regression test fires 3 reloads + 3 saves at once — confirmed it throws the exact `PathNotFoundException` against the old store and passes with the fix; last queued save wins in memory and on disk.

Tests: 33 total, all passing.

Files: `lib/challenge_store.dart`, `test/challenge_store_test.dart`, `TODO.md`

## 2026-09-27 — Restructure: tree is the main screen, with a bottom tab bar

Thomas: "the main page is the unlock tree with a taskbar below" — then chose 3 tabs, profile top-right, settings inside profile ("most apps have it like this").

- `lib/app_shell.dart` (new): `AppShell` = `IndexedStack` of Tree / QuickSwipe / Progress + a floating glass `ShellTabBar`. `extendBody` lets the background run behind the bar while pages' `SafeArea`s keep content above it. Hidden tabs are wrapped in `TickerMode(enabled: false)` so the tree's always-on physics pauses off-tab. Also took over the background-music app-lifecycle observer from the old Home screen.
- Startup (splash → intro on first launch) now lands on `AppShell`. **The old Home menu screen is deleted** (`HomeScreen`, `_ProfileWelcomeButton`, `_MenuProgressAvatar`, `GlassButton`) — it was a class inside `main.dart`, not a whole file, so deleted rather than archived. Its widget test was replaced by `ShellTabBar` tests.
- `lib/profile_avatar_button.dart` (new): the initials + progress-ring avatar, top-right on all three tabs, opens Profile. Profile has a gear icon top-right that opens Settings.
- Tree: no back button (it's the root). The reset button, which sat where the avatar now goes, moved into the ^ progress panel as "Reset progress" (same confirm dialog). The panel is lifted above the tab bar.
- QuickSwipe / Progress: back buttons removed. QuickSwipe now listens to `ChallengeStore` and refreshes completion flags (keeping its review order/position), since it stays alive as a tab while items are checked elsewhere; Tree and Progress already listened.
- Intro slide 3 now says "QuickSwipe or Progress tabs".

Files: `lib/app_shell.dart`, `lib/profile_avatar_button.dart`, `lib/main.dart`, `lib/start_page.dart`, `lib/quick_swipe_page.dart`, `lib/progress_register_page.dart`, `lib/profile_page.dart`, `lib/intro_page.dart`, `test/widget_test.dart`

## 2026-09-27 — Tree interaction: weight, momentum, parallax

Thomas: "using the tree feels a bit off... moving it doesn't feel like it has any weight." Four causes found in `start_page.dart`:

1. **Background never moved when panning** — only scaled with zoom — so bubbles slid over a fixed photo. Now a parallax offset driven by which canvas point is at screen center (not raw translation, which jumps while pinch-zooming), eased with tanh so it saturates inside the image's spare edge. Base background scale 1.2 → 1.3 for room. Constant: `_parallaxStrength = 0.08`.
2. **Massively overdamped physics**: per-frame `velocity *= 0.45` ≈ 48/s decay, so all motion died in ~5 frames. Now damping 12/s (slight give/settle); 30/s (≈ critical, no bounce) when Reduce Motion is on.
3. **Physics was per-frame, not per-second**, while `CADisableMinimumFrameDurationOnPhone` allows 120 Hz — behaviour differed by refresh rate. Now dt-based (px, px/s), dt clamped to 1/30s. Repulsion/spring converted from the old per-frame constants keeping their ratio (600 : 0.09 → 670000 : 100 per s²), so the settled tree shape is unchanged.
4. **Dragged bubbles had no momentum** (stopped dead on release). Now keep the fling velocity (screen px/s ÷ zoom, capped at 2500 px/s), and the held bubble lifts to 1.08× (off under Reduce Motion). The physics doesn't move a bubble that's under a finger.

Not changed, noted for later: while a bubble is expanded, the physics tick re-centres the camera on it every frame, so you can't pan until you close it. The O(n²) per-frame physics (known issue 11) is unchanged, but it now pauses on other tabs via `TickerMode`.

Feel is subjective — tuning constants are grouped at the top of the physics code. Verified: analyzer clean, 33 tests pass, runs on the simulator without errors; the feel itself is for Thomas to judge.

Files: `lib/start_page.dart`
Commit: f1df17b

## 2026-09-27 — Seamless startup: no more white → black → splash

Thomas: on launch you saw a white screen, then black, then the startup screen. Three phases: (1) the native iOS launch screen was still Flutter's white template; (2) StartupScreen's first frames drew before `assets/background.jpg` (3840×2160) had decoded, so only its dark Scaffold colour showed; (3) then the photo and leaf animation.

- `LaunchScreen.storyboard`: background #0A0F0A (StartupScreen's colour), image view pinned to all edges with aspect-fill (native equivalent of `BoxFit.cover`).
- `tool/generate_launch_image.py` (new): pre-blends the background photo at 30% over #0A0F0A — exactly what StartupScreen draws — into `LaunchImage.imageset` (single 1920×1080 PNG, ~2.2 MB; replaces Flutter's placeholder). Re-run if the background or splash colours change.
- `main()` calls `deferFirstFrame()`; StartupScreen precaches the photo in `didChangeDependencies`, then `allowFirstFrame()` and only then starts the sound, animation and 4.2s timer (the sound used to play behind the white screen). 2-second timeout so a failed decode can't leave the app stuck on the launch screen.

iOS caches launch screens: to see a change on a device/simulator, delete the app first (reinstalling from `flutter run` isn't enough). The simulator copy was uninstalled to test this, which reset its local data.

Verified: analyzer clean, 33 tests pass, fresh install launches without errors. The visual transition itself is for Thomas to confirm on a cold start.

Files: `ios/Runner/Base.lproj/LaunchScreen.storyboard`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/`, `tool/generate_launch_image.py`, `lib/main.dart`

---

## 2026-10-03 — EcoSteps runs in the browser

Thomas: "lets do the app in the browser." Earlier (2026-09-28) I'd found `flutter build web` succeeds but the app was broken at runtime: progress saving used `dart:io` `File`, which doesn't exist in a browser, so the tree came up empty and the console filled with errors. Now it runs.

- **Storage seam** (`lib/text_store.dart`, `lib/file_text_store.dart`): `ChallengeRepository` needs only named JSON text blobs (read/write/exists/delete), so it now takes a `TextStore`. `FileTextStore` is the old behaviour unchanged (real files, `.tmp` + atomic rename). `PrefsTextStore` keeps each blob as a `SharedPreferences` string (`store.<name>`) → `localStorage` on the web. `createDefaultTextStore()` picks by `kIsWeb`. `editableFilePath()` is now `@visibleForTesting` and throws on the web store; new `exportJson()` replaces it for real use.
- **Export/Import** (`settings.dart`) no longer pass file paths: export shares `XFile.fromData(...)` (a download in the browser), import reads `FilePicker` bytes (`withData: true`). `dart:io` now appears only in `file_text_store.dart`.
- **Firebase on web**: ran `flutterfire configure --platforms=ios,web` — registered a web app in `ecosteps-d60b6` (`1:104386364831:web:6b9e9a27753b468b1329aa`), `firebase_options.dart` regenerated (iOS config untouched).
- **Firebase-unavailable crash fixed**: `main()` promised the app stays usable if Firebase can't start, but Profile would have thrown (`FirebaseAuth.instance` without an app). `AuthService.isAvailable` (`Firebase.apps.isNotEmpty`) now guards `currentUser`/`authStateChanges`, and Profile hides the Account card when it's false.
- **Notifications are a no-op on web** (`NotificationService.isSupported`), and Settings hides that section there; nothing in a browser tab can schedule a daily reminder.
- **Tree camera**: the opening position was hard-coded for a 402pt-wide phone (`+200, +400`), putting the Start bubble off-centre on anything else. Now centred on the real screen size (`didChangeDependencies`) — fixes the browser and iPad.
- Web page title/description/manifest said "flut" / "A new Flutter project"; now EcoSteps, with the manifest colours set to the splash's dark.

Tests: 6 new (`test/prefs_text_store_test.dart`: the store, plus the repository's seed/save/reload and export→import→backup→restore flow on the browser store). 39 total, all passing; the existing file-store tests ran unchanged through the new interface.

**Verified in a real browser** (release build served locally): intro → tree centred → open Start → Unlock Tier → reload → unlocked bubbles come back from `localStorage`; Profile and Settings render (no Notifications/Developer sections); no console errors. Started from cleared storage to confirm the app writes only the intro flag and the challenge data on its own (an earlier `unlocked_nodes` I saw was from my own click).

**Not verified**: signing in / Firestore sync on web (needs an account, which I can't create); the browser export download and import file dialog; audio autoplay (browsers block sound until a tap); a rebuilt iOS device/simulator build (the changes are Dart-only; analyzer clean, tests pass).

**Limitations to know**:
- Browser progress lives in that browser's `localStorage`: separate from the phone, lost on "clear site data". The Firestore sync is one-way (a summary for friends), so it does not carry progress between devices; that needs the merge/conflict design in the P3 list.
- The UI is phone-designed and stretches on a wide window; no width cap or responsive layout yet.
- Sign in with Apple stays off. Not deployed anywhere; hosting is a separate decision (and Firebase Auth's authorised domains would need the live domain).
- `flutter build web` warns `flutter_timezone`'s web code isn't WebAssembly-compatible (only matters for `--wasm` builds).
- **Stray file change**: `analysis_options.yaml` keeps getting an `analyzer: exclude:` block (build, android, ios, web, windows, macos, linux) that I didn't write — first after `flutterfire configure`, then it reappeared (modified at exactly 18:30:00, so likely a scheduled/automatic process). I reverted it once; it came back. Initially left uncommitted; Thomas then chose to keep it, so it was committed afterwards. It only stops the analyzer scanning generated and platform folders.

Files: `lib/text_store.dart`, `lib/file_text_store.dart`, `lib/challenge_repository.dart`, `lib/challenge_store.dart`, `lib/settings.dart`, `lib/auth_service.dart`, `lib/profile_page.dart`, `lib/notifications.dart`, `lib/start_page.dart`, `lib/firebase_options.dart`, `firebase.json`, `web/index.html`, `web/manifest.json`, `pubspec.lock`, `test/prefs_text_store_test.dart`

---

## 2026-10-03 — Web app published on Firebase Hosting

Thomas: "can you put it on a web app" → **https://ecosteps-d60b6.web.app** (free Spark plan, same Firebase project). This is **public**: anyone with the address can open and use it.

- `firebase.json` got a `hosting` block: serves `build/web`, SPA rewrite to `/index.html`, and `Cache-Control: no-cache` on `/`, `/index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `version.json`, `main.dart.js` — those filenames never change between releases, so without it returning visitors keep running the previous version. The rule for `/` was added after the first release; the CDN's copy of that first response briefly showed `max-age=3600` and expires on its own (fresh requests already get `no-cache`).
- Two releases were published this session (the second only added the `/` header rule).
- **To update the live site:** rebuild with `flutter build web --release --no-wasm-dry-run`, then run the Firebase CLI's hosting deploy for project `ecosteps-d60b6`. Note that Claude Code's auto-mode safety check blocked one later command as a "production deploy" (a plain file edit whose text mentioned deploying), so expect to run deploys yourself or approve them.
- Firebase Auth already authorises the default `web.app` / `firebaseapp.com` domains, so no console change was needed (a custom domain would need adding).

Verified on the live address in a real browser, from cleared storage: the intro starts at slide 1, Profile loads with the Account card (so Firebase starts on the live domain), no console errors; response headers and `<title>EcoSteps</title>` checked with curl. (An intro that once opened on slide 2 in my test browser did not reproduce from clean storage — a test-pane artifact.) Not verified on the live site: sign-in and Firestore sync, Export/Import, audio.

**What's live is the working tree at deploy time, not a commit** — the web changes from the previous entry were still uncommitted, so the live site isn't reproducible from git until they're committed.

Things to know: anyone can create an email account in this Firebase project through the site (Firestore rules keep each account's data to itself, but there's no abuse protection such as App Check); the web app's Firebase API key is public by design. `build/web` is ~47 MB (mostly CanvasKit); Spark's free hosting allowance (10 GB stored, ~360 MB/day transfer) is plenty for personal use but would be felt if the link spread widely.

Files: `firebase.json`

## 2026-10-03 — Shorter web address: ecosteps.web.app

Thomas didn't want "d60b6" in the address. The Firebase **project ID can't be changed**, and the default hosting site is always named after it, so instead created a second site in the same project: `firebase hosting:sites:create ecosteps` → **https://ecosteps.web.app** (also `ecosteps.firebaseapp.com`). Site names are claimed globally; "ecosteps" was free. `firebase.json` now has `"site": "ecosteps"` in the `hosting` block, so deploys go to the new site. Update with the same build/deploy steps as the previous entry.

**The old address https://ecosteps-d60b6.web.app was switched off** at Thomas's request (`firebase hosting:disable --site ecosteps-d60b6`): it now answers 404 "Site Not Found", and `ecosteps.web.app` was confirmed still serving afterwards. It's reversible — deploying to that site again turns it back on. One thing to watch: the old site is the project's *default* hosting site, and Firebase serves its reserved auth pages (`/__/auth/action` for password-reset and email-verification links, `/__/auth/handler` for Google/Apple sign-in redirects) from the default domain `ecosteps-d60b6.firebaseapp.com`, which is also the `authDomain` in `firebase_options.dart`. Nothing in the app uses those yet (no password-reset UI, Apple sign-in is off), but when they're added, check they still work; if not, re-enable the default site with a minimal deploy, or switch the auth domain to the new site.

Verified on the new address in a real browser from clean storage: intro, Profile with the Account card (Firebase starts), no console errors; `Cache-Control: no-cache` and the EcoSteps title via curl. Not verified: whether `ecosteps.web.app` is in Firebase Auth's authorised domains. Email/password sign-in doesn't depend on it, but password-reset links, and any future Google/Apple sign-in, do — check Firebase console → Authentication → Settings → Authorized domains if those misbehave. A custom domain (e.g. a purchased `.app`) is the only way to drop `.web.app`.

Files: `firebase.json`

## 2026-10-03 — Stable ids for checklist items (step 1 of per-account sync)

Thomas wants swaps stored per account so progress follows them between devices. Plan (agreed in chat, nothing built beyond this step): one Firestore doc `users/{uid}/progress/state` holding done-swaps as `itemId → timestamp` (unticking = timestamped "undone"), merged per item newest-wins, plus the unlocked tiers; local store stays the source of truth; pull-merge-push on sign-in; snapshot listener into `ChallengeStore`; per-account local data if a different account signs in. This entry is step 1: ids.

Why ids: a swap was identified only by its label (editable in Playground) or its list position (changes on add/remove). Neither can be matched across devices.

- `ChecklistItem.id` (required). Seed items now spell out readable ids in `assets/data/challenge.json` (118 items, `kitchen.metal-knives` style: slug of challenge + slug of label; the seed file's items changed from bare strings to `{"id","label"}`). Seed items without an id still get the same derived id at load (`ChecklistItem.derivedId`). Items added in Playground get a random `u-…` id (`ChecklistItem.create`).
- **Migration** (`ChallengeRepository._assignItemIds`, runs in `loadChallenges`): a saved item with no id (old bare-string or map format) takes the id of the seed item with the same label in the same challenge, so existing ticks and the shared identity are kept; anything else (user-added or reworded) gets a fresh random id. Present ids are kept; a repeated id (hand-edited/double import) is replaced, so ids are unique across the whole catalog. The load already rewrites the file, so the ids are persisted straight away. Imports of old exports are migrated on the next load.
- Known limit: an item the user reworded *before* this update can't be matched to its seed item, so it gets a user id and would not line up with the same swap on another device. Renames after this update keep the id.
- Nothing reads the ids yet (QuickSwipe still finds items by challenge + index); they're groundwork for the sync merge.

Tests: 5 new in `test/challenge_repository_test.dart` (seed ids unique/readable; legacy save keeps ticks and gains ids; ids stable across reloads; repeated id replaced; rename keeps id). 44 total, all passing; analyzer unchanged (55 existing infos, no new). Not run on a device/simulator.

Files: `lib/challenge_model.dart`, `lib/challenge_repository.dart`, `lib/playground.dart`, `assets/data/challenge.json`, `test/challenge_repository_test.dart`, `test/challenge_model_test.dart`, `test/progress_summary_test.dart`

## 2026-10-04 — Performance check: native is fine, the browser version is not

Thomas saw low frame rates and jittery tree bubbles in the iOS simulator (debug build) and in the live web app on his phone. Findings:

- **No code regression found.** Nothing since the Sept 27 physics/tab-bar work touches how the tree is drawn or moves; today's changes (web support, storage, hosting, item ids) don't either, and the live web app doesn't even contain the item-id commit.
- **Simulator:** debug-only (Flutter can't run release or profile on the iOS simulator), and at the time the Mac was overloaded (load average ~230, swap full after 6 days uptime). Fine again after a restart.
- **Native release build on the iPhone** (installed 2026-10-04 with `flutter build ios --release` + `flutter install --release`): Thomas confirms the app "is working great".
- **Browser version on the phone: not smooth.** Recorded in `TODO.md` (P2 — Web version) with suspects: per-bubble blur, per-frame O(n²) physics with a full `setState`, and the large parallax background through CanvasKit. Not investigated or measured yet.
- Side effect to know: `flutter install` uninstalls the old copy first, so the phone's local progress was reset by it.

No code changed in this entry.

## 2026-10-04 — Tree zoom limits and touch feel

Thomas wanted the tree to feel more grounded. All in `lib/start_page.dart`:

- **Zoom limits are now fixed: 0.7× out, 1.1× in** (the tree opens at 1.0×; it used to allow 0.2×–4×). Tried a user-facing zoom meter/slider first; Thomas didn't want it, so it was removed (it also persisted a value that overrode the default, which caused confusion).
- **Rubber-band at the limits:** `InteractiveViewer` allows 12% past either limit (`_zoomGive`); on release `_settleZoom()` eases the view back (about the screen centre, `easeOutCubic` on the shared camera controller; snaps with reduced motion).
- **Longer glide** after letting go of a drag: `interactionEndFrictionCoefficient: 0.003` (default 0.0000135; roughly 2× longer and farther). Keep it below ~0.005, because Flutter multiplies it by 200 for the pinch glide and a value ≥ 1 would make that grow instead of decay.
- **Touch feedback:** a pressed bubble dips to 0.93 and springs back with a slight overshoot (`easeOutBack`); a dragged one still lifts to 1.08; skipped with reduced motion. **Haptics:** light tap when a bubble opens/closes, medium on Unlock Tier (no-op on web; there is no Settings toggle for it).
- Not verified on a device: only built and run in the debug simulator (which can't show haptics and runs slower than a release build). The settle animation and the library's own glide both write the camera matrix after a pinch, so a pinch that ends with speed may look odd; check on the phone.

Also found this session (no code): low frame rates in the simulator were a debug build plus an overloaded Mac, and the browser version is slow on phones while the native release build is smooth — see the previous entry and `TODO.md`.

Files: `lib/start_page.dart`

## 2026-10-04 — iOS project moved to Swift Package Manager (done by Flutter)

Not something I chose: the first iOS builds of the session made Flutter migrate the iOS project automatically, so the plugins that support it (Firebase etc.) now come in through Swift Package Manager instead of CocoaPods. Thomas approved committing it. Reverting wouldn't stick, since Flutter reapplies it on each iOS build unless disabled (`flutter config --no-enable-swift-package-manager`).

- `ios/Podfile.lock` shrank from ~1500 to ~27 lines (the migrated plugins left it; the rest stay on CocoaPods).
- `project.pbxproj`: registers `FlutterGeneratedPluginSwiftPackage`. `Runner.xcscheme`: pre-build action running Flutter's `xcode_backend.sh prepare`.
- `Package.resolved` (in `Runner.xcworkspace` and `Runner.xcodeproj/project.xcworkspace`, under `xcshareddata/swiftpm/`) pins the library versions.
- Not committed: `Runner.xcscheme.backup` (Flutter's copy of the old scheme).
- Verified: simulator debug build and an iPhone release build both built and ran. Not verified: a clean checkout on another machine. The first simulator build is slow because the large Firebase binaries (gRPC) are downloaded and unpacked through this.

Files: `ios/Podfile.lock`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`, `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`, `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

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
