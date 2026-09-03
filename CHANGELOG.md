# Changelog

## 1.0.1 — 2026-09-03

Clean Up: clears permissions left behind by apps that no longer exist on disk, with Apple's `tccutil`, one entry at a time, after showing the list. Entries for installed apps, path-based entries and Apple's own are always skipped. `permsmac orphans --commands` prints the lines; `--clean` runs them.

## 1.0.0 — 2026-09-03

First release. Reads both permissions databases, groups grants by what they let an app do, keeps a history and shows changes since a chosen date, lists launch agents, daemons and login helpers, notifies when an app gains a permission that can see or control everything, opens the right System Settings pane, and has a command line with JSON output.
