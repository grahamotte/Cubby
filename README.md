# Cubby

Cubby is a fast, simple file manager for macOS, built as a daily replacement for Finder and inspired by QSpace Pro. It browses folders in list, icon, column, and gallery views, splits a window into up to four panes, and keeps a sidebar of nested groups of your favorite folders.

Cubby is built on [Code Moto](https://github.com/grahamotte/CodeMoto), a shared foundation for a Rails API, a React website, native Apple apps, and project tooling. This repository keeps its own Git history and configuration, and merges improvements from Code Moto as the foundation evolves.

## Install

```sh
brew install grahamotte/tap/cubby
```

Or download the signed, notarized zip from [Releases](https://github.com/grahamotte/Cubby/releases). Cubby needs macOS 27 or later.

## Features

- List view with sortable, resizable columns and expandable folders; icon and gallery views with Quick Look thumbnails; column view with a preview of the selected file.
- Single, side-by-side, stacked, three-pane, and four-pane layouts, with native window tabs.
- A sidebar of groups that can hold folders and other groups. Rename, reorder, and nest by dragging; drop a folder between rows to add it, or drop files onto a sidebar folder to move them (hold ⌥ to copy).
- Each folder remembers its view, sort, and icon size without writing anything into the folder.
- Copy, cut, paste, drag and drop, rename, duplicate, compress, new folder, Move to Trash, and undo.
- Folders with 100,000+ items load in a fraction of a second.

## Configuration

Cubby keeps everything in `~/.config/cubby`:

- `config.json` — editable by hand (Cubby ▸ Open Config File, ⌘,) and reloaded live:
  - `showHiddenFiles`: `true` or `false`.
  - `defaultView`: the view for folders you haven't customized (`mode`: `list`, `icons`, `columns`, or `gallery`; `sort`: `name`, `modified`, `added`, `created`, `size`, or `kind`; `ascending`; `iconSize`).
  - `terminal`: the app used by Open in Terminal, such as `Terminal` or `Ghostty`.
  - `sidebar`: a list of `{"group": "Name", "items": [...]}` and `{"folder": "~/path", "name": "optional alias"}` entries. Groups can contain groups; add `"collapsed": true` to start a group collapsed.
- `folders.json` — remembered per-folder views, matched by path and file identity so they follow renamed folders.
- `session.json` — open windows, tabs, layouts, and list columns.

Debug builds use `~/.config/cubby-dev` so development never touches your real settings.

## Contributing

Tools:

- `mise test` — run the complete app, web, deployment, and shared-gem test suite
- `mise simulate macos` — build and launch the macOS app
- `mise xcode` — open the Xcode project
- the [publish runbook](runbooks/publish.md) — version, test, sign, notarize, and publish to GitHub Releases

## Local development

Install mise and PostgreSQL, and have PostgreSQL running locally. Apple app development and tests also require macOS with Xcode.

1. Run `mise install` to install the tool versions pinned in `mise.toml`.
2. Create `.env.development` and `.env.production` from `.env.default` and fill in the required values. Projects registered in Mr. Moto with 1Password references can generate them by running Mr. Moto's `mr secrets` in the checkout instead.
3. Run `mise dependencies` to install project dependencies.
4. Run `mise db:migrate` to prepare the development database.
5. Run `mise start` to start the API, background jobs, and frontend sites. It prints the local URLs; the API runs at `http://localhost:3000`.

Non-secret project settings live in `config.json`, including the domain, GitHub repository, database name, subdomains, and app release details. Application credentials live in the gitignored `.env.*` files. Linear, GitHub/Forgejo PR operations, and macOS release uploads use Mr. Moto's central commands; repository-local tokens are not supported.

## Common commands

| Command | Purpose |
| --- | --- |
| `mise test` | Run all test suites, including frontend type checking |
| `mise tsc` | Type-check the frontend |
| `mise console` | Open the Rails development console |
| `mise simulate iphone` | Launch the iPhone app in a simulator |
| `mise xcode` | Open the Apple app project |
| `mise keychain` | Restore keychain settings left by an interrupted signing run; `--repair` resets the login keychain |

Deployment and publishing use the project-specific instructions in [runbooks](runbooks). Mr. Moto owns card tracking, enqueueing, the review workflow, and the Code Moto merge rollout.

## Starting another project

Run `mise spawn Sundial` from this repository with the project's PascalCase name to create a sibling checkout with project configuration, generated environment files, and the `codemoto` remote. The name sets the directory, GitHub repository, and lowercased database name. The new project has no domain; set `domain` in its `config.json` before deploying it. Create its GitHub repository and review its configuration and credentials before using it. Repository registration and scheduling are handled separately by [Mr. Moto](https://github.com/grahamotte/MrMoto). Downstream projects use Mr. Moto's [merge runbook](https://github.com/grahamotte/MrMoto/blob/master/runbooks/merge.md) to bring in updates from Code Moto without replacing their history.

## Repository guide

| Directory | Contents |
| --- | --- |
| `backend/` | Rails API and background jobs |
| `frontend/` | React sites and shared frontend code |
| `apps/` | Native apps and screenshots |
| `gems/` | Shared Ruby libraries |
| `deploy/` | Infrastructure and deployment tooling |
| `publish/` | App versioning, simulation, and publishing |
| `manager/` | Project creation and Code Moto merges |
| `runbooks/` | Deployment and publishing instructions |
| `scripts/` | Scripts behind mise tasks |

See [Apple credentials](docs/apple-credentials.md) for publishing setup and [AGENTS.md](AGENTS.md) for contribution rules.
