# AGENTS.md

## Code Moto

This repo is based on Code Moto. Code Moto is a basis/template repository that provides tools and patterns for downstream repositories. From a downstream repository, the basis repository is typically available at `../CodeMoto`. If the current repository is named `CodeMoto`, changes affect the Code Moto framework itself.

Repositories based on Code Moto may omit components or add their own. Backport broadly useful tools and changes to `CodeMoto` when practical.

The "Repo Specific" section blow contains rules specific to this repo only.

## Project Rules

1. Do not introduce bugs or regressions.
2. Before writing code, find analogous code in the repository and follow its established patterns.
3. Do not add comments to code. Preserve existing comments unless they are incorrect or obsolete.
4. Lint, type-check, and test code changes using the tasks defined in the root `mise.toml`.
5. Use root `mise` tasks instead of invoking underlying tools directly when an applicable task exists.
6. Give every task in the root `mise.toml` a `description` so `mise tasks` lists what it does.
7. Do not create a canvas or visualization unless the user specifically requests one.
8. When opening a git worktree, copy `.env.development` and `.env.production` from the main checkout into the worktree before running tests or mise tasks.
9. All code changes and other changes to tracked repository files need a PR, pushed with `mr push` and opened with `mr pr create`. Operations without tracked repository changes need no PR, empty commit, or branch. Never commit to or push `master`, and never make repository changes outside the PR flow.
10. Work from `origin/master`: start branches from it, and do not rely on local `master` being current.
11. If you spend significant time unnecessarily or the instructions misdirect you, and the issue could be backported to Code Moto (`CodeMoto` / MOTO), report it with enough detail for Mr. Moto to track the basis-repository follow-up. Keep app-specific issues separate.
12. On macOS, run root `mise` tasks from the worktree root in a non-login shell. For Codex `exec_command`, set `login: false` explicitly on each call that runs `mise`, including through wrappers. If Bundler reports system Ruby or a missing Bundler version, check tool resolution and retry the same root task this way before changing dependencies. Confirm the pinned tools with `mise which ruby` and `mise which bundle`; do not install gems into system Ruby, change lockfiles, or downgrade pinned versions to fix a shell-resolution failure.
13. `AGENTS.md` is the only agent-instruction file. Do not add `.agents/`, `.claude/`, `.codex/`, or `CLAUDE.md`; put repeatable operations in `runbooks/`.

## Ruby

- Use `.blank?` and `.present?` for presence checks instead of `.empty?`, `.nil?`, or truthiness checks.
- Do not use `sleep`; use an event- or state-based approach instead.
- Add trailing commas to multiline argument lists and collections.

## TypeScript

- Treat nullable values as both `null` and `undefined`; use `nullish()` in Zod schemas and check for both states.
- Use `pnpm`, not `npm`.
- Use `mise tsc` to type-check.
- Prefer Lodash utilities over custom equivalents when Lodash is already available.
- Use shadcn/ui components.
- Use Tailwind CSS for styling.

## Testing

- Never run network requests, system commands, or application sleeps in tests. Stub those boundaries every time.
- Do not stub other units in a unit test. Only stub network requests, system commands, and sleeps so the real local collaborators and full local surface are exercised together.
- Every business-logic file must have one corresponding unit test file. Source and test files are 1:1.
- Test each business-logic unit thoroughly. Configuration, generated files, framework shells, and other files without business logic do not need tests.
- After every code change, run the whole suite with `mise test`.
- Do not write integration tests.

## Session instructions

Use `origin` as the sole workflow repository remote, preserving its hosting provider and actual default branch. A Code Moto basis remote named `codemoto` and an optional `deployment` remote may also be present. Do not add mirrors or alternate origin names. Fetch before updating default branches, use fast-forward-only pulls, and never force-push a default branch.

For card work, use Mr. Moto's `mr` CLI: run `mr card claim <CARD>` and follow its output, and see `mr --help` for the rest. This repository provides implementation instructions, checks, and operation tooling.

## File Structure

- `runbooks/` - Project operation instructions, such as deployment and publishing.
- `.env.default` - Template for the `.env.*` secret files.
- `.env.*` - Gitignored secrets, identifiers issued or rotated with them, and `RAILS_ENV`/`NODE_ENV`. Do not expose secret values. Mr. Moto generates them from 1Password with its `secrets` command; each item stores one concealed field per env key, labeled with the key name, and the file follows the `.env.default` layout with extra keys at the end.
- `apps/` - The Cubby macOS app and its tests.
- `assets/` - Shared images and media.
- `backend/` - Ruby on Rails API server.
- `config.json` - Non-secret configuration, including mobile app release (`apps`) and subdomain (`subdomains`) settings. Code reads it directly instead of `ENV`. Each subdomain entry has a required `source`: `website` (the Astro site on Cloudflare Workers), `frontend` (a React site in `frontend/subdomains/<name>` served from the droplet), or `backend` (Rails on the droplet). The default layout puts the website at the apex and `www`, the React app at `app`, and the Rails API at `api`. A config with only `website` entries needs no droplet. Optional `redirectDomains` lists other domains that `mise deploy` 301-redirects to `domain` through Cloudflare, keeping the path and query; deploy replaces each redirect zone's Single Redirect rules. Deploy adds Fastmail MX, DKIM, and SPF records to `domain` and every redirect domain.
- `deploy/` - Backend and frontend deployment tooling.
- `docs/` - Project documentation in Markdown.
- `PRODUCT.md`, `DESIGN.md`, `.impeccable/` - Product context and the visual design system (theme roles, type, spacing, components) used by the Impeccable design skill. Update `DESIGN.md` when the look changes; colors live in `Theme` roles with light and dark values.
- `frontend/` - React frontend sites served from the droplet.
- `gems/` - Shared Ruby gems.
- `website/` - Astro marketing website, deployed to Cloudflare Workers by `mise deploy`.
- `manager/` - Project tooling for spawning new apps and Code Moto merges.
- `publish/` - Mobile app versioning, simulators, and App Store publishing. `mise keychain` restores the user keychain search list after a killed signing run and runs before `mise publish`; `mise keychain --repair` resets the login keychain, default keychain, and search list.
- `scripts/` - General-purpose scripts. `scripts/mise/` holds the scripts behind multi-line `mise.toml` tasks.
- `mise.toml` - Project tooling and task definitions.

## Runbooks

Read the relevant runbook when asked to perform an operation:

- [Deploy](runbooks/deploy.md) - Deploy `origin/master` to production and the website.
- [Publish](runbooks/publish.md) - Version and publish configured Apple apps.

Run `mise tasks` to discover available tasks and their descriptions, including development and production debugging tools.

## Repo Specific

### Deployment

This repository is deployed: `mise deploy` publishes only the Astro website in `website/` to Cloudflare Workers at `cubby.directory`, following the [deploy runbook](runbooks/deploy.md). `config.json` has only `website` subdomains, so there is no droplet; do not add `frontend` or `backend` subdomains, which would make `mise deploy` provision one on DigitalOcean.

### Cubby

Cubby is a native AppKit file manager for macOS 27+, meant as a daily Finder replacement. It is distributed as a signed and notarized repository release, not through the App Store, and through the `cubby` Homebrew cask in `grahamotte/homebrew-tap`, which `mise publish` updates from `apps.homebrew` in `config.json` after each release. Keep it simple, fast, and light on options: prefer too few settings to too many. It has no cloud-drive integrations and never writes files such as `.DS_Store` into browsed folders.

### Apple App Architecture

- The app source is in `apps/apple/App`; the Xcode project is `apps/apple/App.xcodeproj` with the `Cubby` scheme. The project uses a synchronized folder group, so new files in `App/` are built automatically.
- `CubbyMain` starts `AppDelegate`, which builds the menu in code (`MainMenu`), restores the session, and owns window and tab creation. There are no nibs or storyboards.
- `Shortcuts` is the one registry of keyboard shortcuts (id, title, section, keys). `MainMenu` takes menu titles and key equivalents from it (a shortcut's extra keys, such as ⌘← for Back, are handled by `BrowserWindow.performKeyEquivalent`, which skips them while a text field is editing), the browser, column, sidebar, and filter key handlers match `KeyCombo`s against it, and the Settings Keyboard Shortcuts page lists it. Add or change a shortcut there, never as a raw key code.
- All state lives in `~/.config/cubby` (`~/.config/cubby-dev` for Debug builds, which compile with `CUBBY_DEV`). `config.json` is the hand-editable config: `showHiddenFiles`, `showDSStoreFiles` (shows `.DS_Store` files while hidden files are shown), `defaultView`, `terminal`, `appearance` (`system`, `light`, or `dark`), `profiles`, and `profile` (the active profile's index). `themes/` holds extra theme JSON files. `folders.json` holds per-folder views and `session.json` holds open windows (each with a pane layout and paths per profile) and list columns. `AppState` owns these stores, watches `config.json` with `PathWatcher`, and reloads it live; when the file is invalid it reports the error and never overwrites it.
- Each `SidebarProfile` (name, SF Symbol icon, `theme` ID, and its own sidebar tree) is a separate sidebar root, like Arc profiles. The active profile's theme is the applied theme, so switching profiles switches the theme; `appearance` stays global. Each window keeps its own pane layout and paths per profile (`ProfileTabs`), swaps them when the profile changes, and opens a profile it hasn't shown yet at that profile's first sidebar folder. Settings shows profiles as accordion rows (one expanded at a time) that rename, re-icon, delete, and pick each profile's theme; the sidebar's bottom bar switches between them when there is more than one. `AppConfig` owns profile edits, gives new profiles the current theme, migrates a legacy top-level `sidebar` into a `Personal` profile, and gives profiles without a theme the legacy top-level `theme` (dropped on the next save). A theme ID with no matching theme is kept and falls back to the default when applied.
- The sidebar is a tree of `SidebarNode` groups and folders. Groups nest; folders cannot hold children, and only folders (not files or packages) can be added. `SidebarTree` owns all tree edits; `SidebarController` renders it, renames inline, reorders by drag, adds folders dropped between rows, and moves (⌥ copies) files dropped onto a folder row.
- Per-folder views (`FolderView`: mode, sort, direction, icon size, list icon size) are stored in `FolderViewStore` keyed by path plus device and inode, so a view follows a renamed or moved folder. Folders without an entry use `defaultView`; entries equal to the default are not stored.
- `DirectoryReader` lists folders with `getattrlistbulk` for speed on folders with 100k+ entries and falls back to `FileManager` where unsupported. `DirectoryModel` reads, merges, sorts, and filters off the main thread, reuses unchanged `FileItem` instances, and reloads through `PathWatcher` with a delay that scales with the last load time. Keep per-item work lazy and per-row work cheap.
- Windows have no tabs; splits come from pane layouts. `BrowserWindowController` holds the full-height sidebar (settings button, a spinner once the task queue has been busy for half a second, and profile switcher at its bottom; groups are added and renamed from its context menu), a `TopBar` (path breadcrumb, filter, view mode, and layout), and a `PaneLayout` of `PaneController`s with no status bar, and swaps the pane area for `SettingsController` (settings page over `config.json`) when the gear or ⌘, is used; top bar and menu actions reach the active pane through `supplementalTarget(forAction:sender:)`. Each pane hosts one `FileBrowser`: `ListBrowser` (outline with expandable folders and configurable columns; the optional Count column uses `FolderCounter`, which counts visible folder rows off the main thread and recounts on FSEvents), `IconBrowser`, or `ColumnBrowser`. `PreviewView` and `ThumbnailCache` show Quick Look thumbnails; Space opens the Quick Look panel. Each pane keeps an in-memory `ScrollMemory` (LRU of top-item anchors per folder) and restores it after a folder loads; explicit selections still scroll into view.
- `FileOperations` performs moves, copies, trash, renames, and creation with conflict choices and is the tested core. `FileActions` runs it through `TaskQueue`, a serial queue off the main thread that keeps an in-memory log of each task (state, times, transfers, errors) for a future task list and undo, and applies each task's `PendingChange` the moment it is queued: `PendingChanges` hides moved and trashed items and shows placeholders for moved and copied items in their destinations, every `DirectoryModel` applies them, and folders reread when the task ends. It asks about conflicts, updates sidebar paths after moves, and registers one undo group per operation on the shared undo manager (`groupsByEvent` is off; undo does not register redo).
- Every UI color comes from `Theme` roles, which resolve the active `ThemeDefinition` (from `ThemeLibrary`: built-ins plus `themes/*.json`) for the light or dark appearance at draw time. `AppState` reloads themes when files change and `Theme.apply` sets the app appearance and redraws open windows. Do not use system label or accent colors in views; add a role instead.
- System boundaries are the file system and Quick Look; tests use temporary directories.

### Apple Workflow

- `mise test` runs the repository suite, including the `CubbyCore` package tests in `apps/apple/Tests`, which compile the non-UI files listed in `Tests/Package.swift`. Add new business-logic files to its `sources` and app-only files to its `exclude`.
- Use `mise simulate macos` to build and launch the Debug app and `mise xcode` to open the project.
- Screen capture is not available to agents. To check UI, run the Debug build and use `mise app:debug` with the `DebugHooks` commands, for example `mise app:debug "snap|/tmp/cubby.png"`, then read the PNG. Snapshots do not render source-list selection vibrancy.
- Opening protected folders such as Desktop prompts for access; reads happen off the main thread so a pending prompt does not hang the UI.
- Use the [publish runbook](runbooks/publish.md) for versioning and the signed, notarized GitHub release workflow.
