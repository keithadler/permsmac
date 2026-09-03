# Changelog

## 1.0.5 — 2026-09-03

Leftovers stored by path, which tccutil cannot address, now show a "Remove in System Settings…" button on the row. An app's main executable is no longer repeated in its name.

## 1.0.4 — 2026-09-03

Clean Up actually clears now. Apple's `tccutil` refuses any bundle identifier that is not on disk (error -10814), which is every removed app. For each app, Clean Up now creates an empty placeholder bundle with that identifier in its own Application Support folder, registers it for the length of one `tccutil reset All` call, then unregisters and deletes it. Tests cover the placeholder's contents, the order of operations, and removal on failure.

## 1.0.3 — 2026-09-03

Clean Up now makes one tccutil call per app (`reset All`) instead of one per entry, runs in the background with a progress count instead of freezing the window, and shows a results list with any tccutil error. The overview refreshes when the sheet closes.

## 1.0.2 — 2026-09-03

Fixed: changes made a moment ago (a Clean Up, or a switch flipped in System Settings) did not show until macOS folded its write-ahead log back into the database. The app now reads from a private copy of the database and its log, so what it shows is current. Apple's files are still never written to.

## 1.0.1 — 2026-09-03

Clean Up: clears permissions left behind by apps that no longer exist on disk, with Apple's `tccutil`, one entry at a time, after showing the list. Entries for installed apps, path-based entries and Apple's own are always skipped. `permsmac orphans --commands` prints the lines; `--clean` runs them.

## 1.0.0 — 2026-09-03

First release. Reads both permissions databases, groups grants by what they let an app do, keeps a history and shows changes since a chosen date, lists launch agents, daemons and login helpers, notifies when an app gains a permission that can see or control everything, opens the right System Settings pane, and has a command line with JSON output.
