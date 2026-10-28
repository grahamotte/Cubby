# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Apple's native design language, shipped as a native AppKit app for macOS 27+ (not iOS, not web, not Catalyst). Impeccable has no macOS value, so `ios` stands in. Follow the HIG for Mac: pointer and keyboard first, so 44 pt touch targets, tab bars, edge-swipe back, and 17 pt Dynamic Type body sizes do not apply; dense 13 pt UI text and 24-28 pt rows are normal. Verify UI with the Debug build and `mise app:debug "snap|/tmp/cubby.png"` (see AGENTS.md), not the iOS Simulator.

## Users

Primarily Graham, using Cubby as an all-day Finder replacement on his own Macs. Other people who install it from the Homebrew cask are welcome, but design decisions optimize for this one expert, keyboard-heavy daily user and his taste over broad appeal or discoverability.

## Product Purpose

Cubby is a fast, simple file manager that replaces Finder for daily browsing, organizing, and moving files. Success is that it is the file manager he reaches for by default: instant on huge folders, calm to look at, and never in the way of the files themselves.

## Positioning

A personal, opinionated Finder replacement inspired by QSpace Pro, but deliberately smaller: few settings, no cloud-drive integrations, and no writing of `.DS_Store`, `.qspacesettings`, or any other file into browsed folders. All state lives in `~/.config/cubby` as hand-editable JSON.

## Operating Context

- Used all day alongside a code editor, terminal, and browser; often on large and deeply nested folders (100k+ entries).
- Navigation via a user-organized sidebar of nested groups and folders, a path breadcrumb, and the keyboard.
- One window shows one or more split panes (single, side by side, stacked, three, four). Windows have no tabs.
- View modes per folder: list (expandable outline with configurable columns), icons, columns, and gallery, with Quick Look thumbnails.
- Settings live on a page in the main pane and in `config.json`, which can be edited by hand and reloads live.
- Distributed as a signed, notarized GitHub release and the `cubby` Homebrew cask; not on the App Store.

## Capabilities and Constraints

- Moves, copies, trash, rename, and new folder/file with conflict choices and undo; drag and drop between panes, the sidebar, and other apps.
- Per-folder views follow a folder across renames and moves.
- Must stay fast: per-item work is lazy and per-row drawing is cheap; no per-row visual effects that cost time on huge folders.
- Keep it simple and light on options: prefer too few settings to too many.
- Themes: Settings > Appearance picks a theme and a color scheme (System, Light, Dark). Each theme has a light and a dark variant that follows the appearance; built-ins are Workbench, Bubblegum, Grove, Ocean, Ember, and Iris, and extra themes are JSON files in `~/.config/cubby/themes` (not surfaced in the UI).

## Evidence on Hand

- App icon and repository assets in `assets/` and `apps/apple/App/Assets.xcassets`.
- No testimonials, user counts, press, or benchmarks exist; do not invent them.

## Product Principles

1. Files and thumbnails come first; chrome recedes.
2. Speed is a feature: nothing visual may make large folders slow.
3. Fewer options, better defaults.
4. Never touch the user's folders with app metadata.
5. Everything is reachable from the keyboard.

## Accessibility & Inclusion

- Light and dark appearances both look intentional and follow the system setting; future themes each ship both variants.
- Full keyboard operation with visible focus.
- Respect Increase Contrast, Reduce Transparency, and Reduce Motion.
- Stay responsive on folders with 100k+ items.
