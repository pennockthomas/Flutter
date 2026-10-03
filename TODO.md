# EcoSteps — Remaining work

Updated: 2026-09-27.

This checklist consolidates the completeness review and remaining roadmap work. New improvements are proposals, not confirmed bugs. Prioritize a dependable local iOS app before expanding into accounts and social features. Check items off only when implemented and verified; keep the history in `AI_LOG.md`.

## P1 — Trustworthy features and safe progress

- [x] Hide or clearly label the sample Friends screen until real friends exist; make its demo status visible on the screen itself.
- [x] Disable or explain inactive Share Total Progress, Share Area Progress, Share Checked Items, and Friend Updates controls.
- [x] Keep cloud sync, authentication, and private-item descriptions consistent with the app's actual local-only behavior.
- [x] Confirm before importing a file that replaces current progress; explain what will be replaced.
- [x] Preserve a recoverable backup before importing, and provide a restore path.
- [x] Make saves resilient to interrupted writes, using a temporary file and atomic replacement where supported.
- [ ] Handle save failures without leaving in-memory progress and stored progress inconsistent; show a useful error and allow retry.
- [ ] Show a clear load-error state with retry/recovery instead of silently presenting an empty profile or challenge list.
- [x] Validate imported challenge relationships as well as JSON structure, including duplicate IDs, missing references, and cycles that the app cannot safely handle.
- [ ] Verify export/import scope: challenge data lives in JSON while unlocked nodes and category progress also use preferences. Define whether backups include these and ensure a round trip restores the promised state.

Relevant files: `lib/challenge_repository.dart`, `lib/challenge_store.dart`, `lib/settings.dart`, `lib/friends_page.dart`, and screens that load challenge data.

## P1 — Tree performance and interaction

- [ ] Profile the tree on a physical iPhone, including idle time and a larger challenge graph.
- [ ] Stop or reduce physics updates once the graph settles; resume when interaction requires them.
- [ ] Measure and reduce unnecessary widget rebuilds and blur rendering work.
- [ ] Check that movement does not make bubbles difficult to tap or read.
- [ ] Define and verify reduced-motion behavior for remaining movement, including startup and continuous tree motion.
- [ ] Recheck zoom, pan, expansion, completion, and reset after performance changes.

The simulator's Metal crash does not establish that tree physics caused it. Treat performance as a separate, measurable concern.

Relevant files: `lib/start_page.dart`, `lib/main.dart`, `lib/app_settings.dart`.

## P2 — Notifications

- [ ] Allow users to select and persist their daily reminder time; replace the pending reminder when it changes.
- [ ] Show whether iOS notification permission is granted, denied, or not yet requested, with useful guidance when disabled.
- [ ] Review when permission is requested so the prompt has context and respects disabled notification preferences.
- [ ] Test cancellation: schedule a reminder, switch Daily Reminders off, and confirm no delivery.
- [ ] Test next-day repetition and ensure relaunching does not create duplicate reminders.
- [ ] Test scheduling around midnight, daylight-saving changes, and timezone changes; handle timezone lookup failure explicitly.
- [ ] Verify reminder delivery on a physical iPhone with the app in the background and after termination.
- [ ] Verify Milestone Alerts when completing a challenge from Start, Playground, and Progress Register.
- [ ] Verify Milestone Alerts off suppresses notifications and ordinary checklist changes do not trigger completion alerts.
- [ ] Handle notification initialization or scheduling failures gracefully and surface relevant failures in Settings.
- [ ] Decide whether to add total-progress milestones; if added, define thresholds and avoid unwanted repeated alerts.

Already verified: the daily reminder delivered in the iOS simulator, confirmed by Thomas's screenshot. The normal 6pm build was restored afterward. Cancellation and next-day repetition are not yet verified.

For a short delivery test, run `flutter run --dart-define=TEST_DAILY_REMINDER=true`. This debug-only option schedules the existing repeating reminder two minutes ahead. Run without the flag afterward with reminders enabled to restore 6pm, or disable reminders to cancel it.

Relevant files: `lib/notifications.dart`, `lib/settings.dart`, and the three checklist screens.

## P2 — Everyday usability and consistency

- [ ] Replace the hardcoded identity with an editable, persisted local name and derived initials; accounts are not required for this. **Now blocks Phase 3c:** every user currently sees "Thomas Pennock" / "TP", and `ProgressSync` falls back to `AppUser.name` for email accounts, so a friend signing up would appear to others as "Thomas Pennock". Ask for a display name in the create-account form and use it everywhere.
- [x] Make the displayed impact level reflect progress, or remove the static "Getting Started" label. (Removed with the Settings info rows, 2026-09-27.)
- [ ] Read the displayed version from package metadata; Settings currently says 1.0.4 while `pubspec.yaml` says 1.0.0+1.
- [ ] Verify the support contact is real and usable before presenting it to other users. (`support@ecosteps.app` was removed from Settings on 2026-09-27; add a real contact back only once one exists.)
- [ ] Add concise help explaining challenge unlocks, checklist progress, editing, reset, and backup behavior.
- [ ] Test first launch and empty, loading, and error states with someone unfamiliar with the app.
- [ ] Check text scaling, VoiceOver labels, touch targets, and text readability over the background image.
- [ ] Test small screens, landscape, keyboard interaction, and iPad if those layouts remain supported. Recommendation: lock iPhone to portrait — `Info.plist` allows landscape but no screen is designed for it.
- [x] Decide whether Playground is a user feature or a developer tool, and label/expose it accordingly. (Done 2026-09-27: it's a developer tool. Removed from the Home menu; reachable only via Settings → Developer, which exists only in debug builds (`kDebugMode`). Release builds, including installs on Thomas's phone, have no Playground.)

## P2 — First-run clarity and product polish

From a fresh-eyes walkthrough on 2026-09-27 (treating the app as a first-time user on a clean simulator install). Proposals, not confirmed bugs — check with Thomas before implementing the larger ones.

Bigger:
- [x] Explain what the app is for on first launch. (Done 2026-09-27: 3-screen intro between the splash and Home on first launch only (`lib/intro_page.dart`, flag `onboarding.intro_seen`), plus a "Tap Start to begin" hint under the lone Start bubble until it's opened. Replay via Settings → Developer in debug builds. No Home tagline — the splash already says "One step closer to plastic-free".)
- [ ] Decide the role of the three ways to check off the same 118 items (Start tree, QuickSwipe, Progress Register) — nothing explains how they differ. Suggestion: the tree is the main "journey", Progress Register is the list view, and QuickSwipe is offered once at the beginning ("already own some of these? swipe through them").
- [ ] Give each swap meaning: why it's better, what it replaces, rough cost. Continue the product illustrations (one done so far — see `tool/generate_product_icons.py`). Consider impact feedback when checking items off (e.g. "≈ 40 plastic items avoided a year").

Smaller:
- [ ] Show overall progress (e.g. 0/118) on Home; it's currently only visible behind the TP avatar.
- [ ] Replace internal jargon with plain words: "Unlock Tier" → e.g. "Show next steps"; "Parent: Start" → "Part of: Kitchen"; "parent bubbles" in the search placeholder; consider renaming "Progress Register" (e.g. "My swaps").
- [ ] Start screen icons: the top-right refresh icon resets **all** progress but looks like "reload" — move reset into Settings → Progress & Data (the old "Reset Progress: Available in Start" pointer row was removed with the other info rows, so reset is now only discoverable on the Start screen). Label or explain the bottom-right ^ button, which opens a hidden progress panel.
- [ ] Give the Home menu buttons (`GlassButton`) press feedback (highlight or slight shrink); taps currently feel unresponsive even when they register.
- [x] Trim Settings rows that aren't settings. (Done 2026-09-27: all read-only info rows removed. Local Profile, Friends Preview, Privacy & Security, and Help & Support had nothing else and are gone. Settings now holds only Appearance, Progress & Data, Sounds, and Notifications.)
- [ ] Fix the truncated Progress Register search placeholder ("Search swaps, rooms, or parent bu…").

Quick wins (roughly 15–30 minutes each): display-name field at sign-up (fixes the identity bug above), lock portrait, hide Playground in release, move reset into Settings, rename jargon, button press feedback.

## P2 — Web version

The app now runs in a browser (see `AI_LOG.md`, 2026-10-03); what's left before it's something to share:

- [x] Make the app run in a browser (storage on `localStorage`, Firebase web config, notifications off, tree centred on any screen).
- [ ] Layout for wide windows: the UI is phone-designed and stretches. Probably a centred max-width column on wide screens, or a proper responsive layout.
- [ ] Verify in the browser: sign-in and the Firestore progress sync, the Export download and Import file dialog, and audio (browsers block sound until the first tap).
- [x] Hosting: published 2026-10-03 at https://ecosteps.web.app (Firebase Hosting site `ecosteps`). The old https://ecosteps-d60b6.web.app was switched off. It was the project's default site, which Firebase also uses for its auth action pages — when adding password reset or Google/Apple sign-in, verify those links still work (see `AI_LOG.md`). Still open: confirm `ecosteps.web.app` is in Firebase Auth's authorised domains (matters for password-reset links); whether to keep it public; a custom domain; abuse protection (App Check) now that anyone can sign up. Commit the web changes so the live site matches git.
- [ ] Browser progress is per-browser and lost on "clear site data" — consider a visible export reminder, and decide how it should reconcile with the phone (this is the P3 merge/conflict item: the current Firestore sync is one-way).
- [x] `analysis_options.yaml`: an `analyzer: exclude:` block (build, android, ios, web, windows, macos, linux) kept appearing, added by something other than me. Thomas chose to keep it (2026-10-03), so it's committed. It only stops the analyzer scanning generated and platform folders.

## P2 — Verification before a wider iOS release

- [ ] Add meaningful screen/integration coverage for checklist changes updating all open screens.
- [ ] Cover reset behavior, ensuring settings survive while checklist progress and unlock state reset consistently.
- [ ] Cover import cancellation, invalid imports, failed writes, and backup recovery.
- [ ] Cover notification preferences and scheduling/cancellation behavior without relying only on manual tests.
- [x] Test rapid edits and overlapping loads/saves for lost updates; serialize operations if needed. (Done 2026-09-27: the tab layout made several screens load at once, which collided on the shared `.tmp` save file (`PathNotFoundException`). `ChallengeStore` now runs all disk operations one at a time and shares a single initial load; regression test in `test/challenge_store_test.dart`.)
- [ ] Test physical-device cold launch, relaunch, background/foreground transitions, and interrupted operations.
- [ ] Verify startup sound, background music, completion sound, and unlock sound with their settings enabled and disabled.
- [ ] Run an end-to-end local-user trial: start fresh, complete challenges, edit, export, import, reset, and relaunch.
- [ ] Prepare release identity and metadata, user-facing privacy information, support details, screenshots, and a release-build smoke test.

Baseline: all 18 existing tests passed on 2026-09-26. Most cover models and persistence; there is only minimal widget coverage. Passing them does not verify every screen or notification delivery scenario.

## P3 — Accounts, friends, sharing, and cloud sync

Started 2026-09-27 with Thomas's go-ahead. Backend: Firebase (Auth + Firestore, database in europe-west4). Sub-phases 3a–3e and the data model are in `AI_LOG.md` → "Phase 3 scoping". Done: 3a (auth). In progress: 3b (progress summary sync — code written, needs an end-to-end check with a real sign-in).

- [x] Agree the first release's social scope and whether users can continue without an account. (Accounts are optional; the app stays fully usable signed out.)
- [x] Choose the backend after agreeing data, hosting, privacy, and cost requirements. (Firebase, free Spark plan.)
- [x] Define users, challenges, friendships, invitations, and shared-progress data models.
- [ ] Implement sign-up, sign-in, sign-out, account recovery, and account deletion. (Email sign-up/in/out done. Sign in with Apple is built but hidden until Thomas has a paid Apple Developer account. No password-reset UI or account deletion yet — `AuthService.sendPasswordResetEmail` exists but nothing calls it; account deletion is required by the App Store.)
- [ ] Preserve existing local progress when signing in; define merge/conflict rules before adding synchronization.
- [ ] Implement cloud sync with offline behavior, retries, and visible sync status.
- [ ] Replace the three sample friends with real data and useful empty/loading/error states.
- [ ] Implement friend invitations, acceptance, removal, and appropriate blocking controls.
- [ ] Make progress sharing private by default and explain exactly what each sharing control exposes.
- [ ] Enforce sharing permissions on the backend, including total, category, and checklist visibility.
- [ ] Implement private-item behavior if retained in the product.
- [ ] Implement Friend Updates using real events and respect notification preferences.
- [ ] Test access isolation between accounts, revoked friendships, changed sharing settings, and account deletion.

## Maintenance and explicitly deferred work

- [ ] Avoid rewriting the challenge save file on load when seed merging makes no changes.
- [ ] Replace the template README with setup, architecture, testing, and reminder-test instructions.
- [ ] Refresh the known-issues summary in `AI_LOG.md`; its broad "most Settings toggles are dead" wording predates the completed local features.
- [ ] Decide which additional platforms are supported before extending platform-specific features. Notifications currently initialize for iOS only.
- [ ] If other platforms are targeted, add matching branding/icons, platform configuration, and device testing.
- [ ] Revisit splitting `start_page.dart` and `playground.dart` only when a concrete change justifies it; the earlier decision was to defer a broad refactor.

Do not reintroduce High Contrast Text: it was deliberately removed at Thomas's request. Archive unused whole files rather than deleting them outright, following `archive/README.md`.

## Suggested order

0. Before friends (Phase 3c): fix the hardcoded identity (display name at sign-up).
1. Make incomplete features visibly honest and protect saved progress.
2. Measure and improve tree performance.
3. Finish notification controls and verification.
4. Polish local profile, help, accessibility, and metadata.
5. Complete physical-device testing and a small local-only user trial.
6. Start the social/backend phase only after a separate scope decision.
