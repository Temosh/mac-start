# MacStart

A native app launcher for macOS 27 that brings back the classic Launchpad experience: a fullscreen grid of your apps, opened with a global hotkey.

## Features

- Fullscreen overlay on the main display, with pages, folders, and type-to-search.
- Global hotkey to toggle it. Bind a trackpad gesture to the hotkey with a gesture tool of your choice.
- Hide apps you never launch from the grid.
- Each installed app appears exactly once. The grid follows installs and removals.
- Export and import your full setup (layout and preferences) as one JSON file, for easy migration to a new Mac.

The project is in early development. The current status is in [docs/project-brief.md](docs/project-brief.md).

## Requirements

- macOS 27 or later, Apple silicon.
- Xcode 27.2 or later installed, for the Swift toolchain only. No Xcode project is used.

## Build And Run

```bash
swift build
swift test
scripts/build-app.sh
open build/MacStart.app
```

The app is signed ad hoc for local use. It has no sandbox and is not notarized.

## Download

GitHub Actions builds every push. Tagged versions are published as GitHub Releases. For install and update steps, including how to open a non-notarized app, see [docs/operations.md](docs/operations.md).

## Documentation

| File | Contents |
|------|----------|
| [docs/project-brief.md](docs/project-brief.md) | Goals, non-goals, terminology, open questions |
| [docs/architecture.md](docs/architecture.md) | Source layout, modules, platform choices |
| [docs/domain-model.md](docs/domain-model.md) | Layout model, invariants, export format |
| [docs/ui.md](docs/ui.md) | Overlay and settings behavior |
| [docs/operations.md](docs/operations.md) | CI build, releases, install and update |

## Agent Setup

`AGENTS.md` is the entry point for AI coding agents. `CLAUDE.md` imports it. Shared rules and skills live in `.agents/`.

Agent tools find these rules and skills through local symlinks, which git ignores: `.claude/rules`, `.claude/skills`, and `.clinerules`. After a fresh clone, recreate them:

```bash
python3 .agents/skills/agents-project-setup/scripts/setup.py links .
```

## License

See [LICENSE](LICENSE).
