# AGENTS.md

MacStart is a native macOS 27 app launcher: a fullscreen, Launchpad-style overlay opened by a global hotkey or its Dock icon. It is written in Swift and built with Swift Package Manager only, without an Xcode project. Agents do all the development.

Use this file as the short entry point for Claude Code, Codex, Copilot, Cline, and other agents. Put detailed guidance in `.agents/rules/` and keep provider-specific folders as links or thin references to the same source of truth.

Any convention expected from every agent must be defined in this repository, either directly in `AGENTS.md` or in a referenced file under `.agents/`. Do not rely solely on provider-specific prompts, injected instructions, global configuration, or private agent memory for project rules.

## Before Working

1. Read the project-specific brief when it exists: `docs/project-brief.md`.
2. Read the relevant rules in `.agents/rules/` for the language, framework, and task.
3. Inspect the existing code before making assumptions about architecture or style.
4. Prefer small, focused changes that preserve user work already present in the tree.

## Diagrams

When a diagram would improve communication, use Mermaid wherever Mermaid can express the content. This applies to architecture diagrams, workflows, sequences, state transitions, dependency graphs, decision trees, entity relationships, and similar visual structures.

Do not create ASCII-art, ANSI-art, or Unicode box-drawing diagrams. Use plain prose, lists, or tables only when the content is not meaningfully a diagram or Mermaid cannot express it clearly. Follow `.agents/rules/documentation-and-diagrams.md` for the complete rule.

## Task Notes

Use `.agents/tasks/` for task-specific agent working notes that should persist across sessions, such as investigation findings, implementation plans, decisions, and handoff state. Keep reusable guidance in `.agents/rules/`, project facts and user-facing documentation in `docs/`, and transient scratch notes in the current conversation unless they need to be handed off.

- One folder per meaningful task or workstream: `.agents/tasks/<task-name>/TASK.md`. The uppercase `TASK.md` mirrors the `SKILL.md` convention. Supporting files for the task may sit next to `TASK.md`.
- A task note is created when the task starts, not ahead of it.
- `TASK.md` is self-contained: a fresh session prompted only with `Do task <task-name>` must be able to carry it out. It names any capability the task needs that only one agent or tool has.
- **Finished tasks are deleted.** Before deletion, every settled fact, decision, or reusable finding moves into `docs/` or `.agents/rules/`, and decisions that meet the ADR criteria also get an ADR in `docs/adr/`, so the reasoning survives the deleted task. A task in `depends_on` whose folder no longer exists counts as done.
- Agents never mark a task owned by `human` or `agent+human` as done without the developer's confirmation.
- Link direction: tasks may link to `docs/`, `.agents/rules/`, and other tasks by folder name. Nothing outside `.agents/tasks/` ever links into a task.

`TASK.md` format:

```markdown
---
title: Short imperative title
type: feature        # feature | bug | decision | design | chore | qa
owner: agent         # agent | human | agent+human
status: todo         # todo | in-progress | blocked | review
depends_on: []       # other task folder names
---

## Goal
## Scope
## Acceptance Criteria
## Verification      <!-- tests, commands, manual checks -->
## Notes             <!-- working notes, findings, handoff state while in progress -->
```

## Decision Records

Significant decisions made after the initial project baseline are recorded as ADRs in `docs/adr/`, indexed in `docs/adr/README.md`. Docs hold the current facts; ADRs hold why a decision was made and which alternatives were rejected.

- Do not read ADRs by default. Before proposing to change, reverse, or work around something the docs state as settled, check the index and read the relevant ADR.
- Accepted ADRs are immutable; a changed decision gets a new ADR that supersedes the old one, and the affected docs are updated in the same change.
- Follow `.agents/rules/documentation-and-diagrams.md` for when to write an ADR, the format, and the lifecycle.

## Commands

Run these from the repository root:

```bash
swift build                          # Debug build of all targets
swift test                           # Run unit tests (Swift Testing)
scripts/build-app.sh                 # Release build, assemble build/MacStart.app, ad hoc codesign
open build/MacStart.app              # Run the bundled app
swift format lint -r Sources Tests   # Lint (swift-format bundled with the toolchain)
swift format -i -r Sources Tests     # Format in place
```

Never open or generate an Xcode project. Everything must build from the command line.

## Project

MacStart restores the Launchpad experience removed in macOS 26. It is a personal tool, built and run locally by one user. Core workflows: open the overlay with a hotkey or the Dock icon, search and launch apps, organize them into pages and folders, hide apps, and export or import the full state (layout and preferences). Non-goals: windowed mode, secondary displays, native trackpad gesture handling (external tools map gestures to the hotkey), and App Store distribution.
| File | Purpose |
|------|---------|
| `docs/project-brief.md` | Product context, goals, non-goals, terminology, open questions |
| `docs/architecture.md` | Source layout, module boundaries, platform choices, data flow |
| `docs/domain-model.md` | Layout entities, invariants, reconcile, export/import format |
| `docs/ui.md` | Overlay layout, interactions, settings, accessibility |
| `docs/operations.md` | GitHub Actions build, releases, versioning, install and update |
| `docs/adr/` | Architecture decision records, created when the first post-baseline decision is made |

## Stack

- Swift 6.4 (language mode 6, strict concurrency), toolchain from Xcode 27.2.
- Swift Package Manager, macOS 27+, Apple silicon.
- SwiftUI for views, AppKit for the overlay window, the hotkey, and system integration.
- Swift Testing for unit tests.
- No third-party dependencies. Details: `.agents/rules/stack.md`.

## Rule Index

Use only the rules that apply to the current task:

| File | Purpose |
|------|---------|
| `.agents/rules/stack.md` | Runtime, framework, tooling, dependency, and integration rules |
| `.agents/rules/documentation-and-diagrams.md` | Documentation conventions and mandatory Mermaid diagram rules |
| `.agents/rules/code-conventions.md` | Language-agnostic code conventions |
| `.agents/rules/code-conventions-swift-macos.md` | Swift desktop macOS app conventions |
| `.agents/rules/workflow.md` | Commits, checks by the developer, the developer's focus, and assets |

## Source Layout

- `Sources/MacStartCore/`: Foundation-only library with the model, reconcile, catalog scanning, and persistence. It must not import AppKit or SwiftUI.
- `Sources/MacStart/`: the executable, with the app entry, overlay, feature UI, and thin platform adapters.
- `Tests/MacStartCoreTests/`: unit tests for the core library.
- `Support/`: `Info.plist` and the app icon source, packaged by `scripts/build-app.sh`.
- `.github/workflows/`: the CI build and release workflow.

Full layout and dependency rules: `docs/architecture.md`.
