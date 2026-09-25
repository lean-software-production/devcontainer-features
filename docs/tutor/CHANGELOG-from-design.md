# Changes from the approved design

This log covers the MVP build, made while the owner was away. It records every place where the
build diverges from [`DESIGN.md`](DESIGN.md) as reviewed in PR #4, and why. Entries are
newest-first.

## Integration (2026-09-25)

Proven end to end in a fresh container built from `.devcontainer/tutor` (ports moved to
48886/48887, `/workspaces` bind-mounted) with the scripted provider. Changes made while
integrating:

- **`spec/PROGRESS.yaml` keeps a `history`.** Adopting the next homework used to replace the
  finished homework's progress, so its lesson said "0 of 9 examples hold · Complete ✓" and its
  completion page lost the coach's summary. The previous homework's statuses, `adopted` and
  `summary` now move under `history.<id>` (evidence is left out; it stays in git history).
- **Coach threads work directly in the factory folder** (`host` environment with an unmanaged
  workspace) rather than `project-default`, so the coach always edits the folder whose
  `spec/PROGRESS.yaml` Tutor reads, and side threads share it.
- **The completion page continues a homework that has already started** ("Continue homework N with
  your coach", which opens the existing coach) instead of offering "Start", which would fail.
- **Homework 0's "Coming back later" Example** now says BB home's "Continue with your coach" returns
  to the coach thread; the home section's separate "Open the lesson" opens the lesson.
- **The feature installs the plugin from a user-owned, digest-named copy** in BB's data directory,
  because BB rebuilds `dist/` on every path install.

## Spike results (2026-09-25)

All six probes worked in a containerised BB 0.43.4. The evidence is in `scripts/tutor-dev/` and
the spike notes. Changes that follow from it:

- **Lesson page uses `ThreadChat layout="document"` inside a scroller the page owns.** This
  refines decision 6 / mockup 2A. With `contained`, BB's opaque scroll container hides the grid
  paper and can only be see-through by overriding BB-internal classes. `document` paints no
  background.
- **Every Tutor tool re-checks the calling thread inside `execute()`** (plugin metadata or
  origin), and refuses otherwise. This is new. `configure` scoping controls which tools are
  *offered*, but BB 0.43.4 still runs a plugin tool that a provider calls without being offered
  it. This was reproduced with a scripted provider.
- **The course rail must be selected once.** `experimental_threadList` never wins by default: the
  user picks it under Settings → Appearance → Sidebar, and the choice is stored server-side. The
  feature's start-up script selects it when BB exposes a way to do so; otherwise first run asks
  the student to.
- **The rail works out the active lesson from its own route.** BB passes `activeThreadId` as null
  on plugin pages.
- **The "Continue" section on BB home finds the coach thread itself** (with
  `threads.list({originPluginId})`), because `homepageSection`'s `projectId` is usually null.
- **Directive cards (`::tutor-progress`, `::term`) render in any thread**, not just Tutor's.
  Their attributes are treated as untrusted and validated.
- **A scripted provider plugin becomes the credential-free end-to-end test fixture.** It echoes
  directives and makes real tool calls. This is new; real Claude Code and Codex are not used in
  tests.
- **The plugin is path-installed by a `postStartCommand` that runs after `bb-feature-autostart`.**
  It is idempotent: it skips when the plugin is already installed from the same path. The `bb`
  feature does not export `BB_SERVER_URL`, `BB_DATA_DIR` or `BB_HOST_DAEMON_PORT`, so the `tutor`
  feature sets them for its hooks.
- **Harness ports.** Local development uses 47886/47887 rather than the defaults, so it never
  touches the host's own BB.

## Decisions taken at kick-off (2026-09-25)

- **Stacked on PR #3.** The `tutor` feature depends on the unmerged `bb` feature, so this branch
  (`tutor/mvp`) is based on `bb/add-bb-standalone-devcontainer-feature`.
- **bb-app pin bumped from 0.43.3 to 0.43.4.** 0.43.4 is npm `latest` and bundles host plugin SDK
  0.5.9. The plugin compiles against that exact SDK, not npm's newer 0.5.24.
- **Tutorial repo is optional for the MVP.** The engine reads `course.yaml` when present and
  otherwise falls back to parsing the ledger table in `docs/iterations/README.md`.
  `course.yaml` and the `coach-me.md` change go to the tutorial repo as a separate PR and are not
  blocking.
- **Codespace entry point.** `.devcontainer/tutor/devcontainer.json` in this repo combines `bb`
  and `tutor`, and clones the public `tutorial` repo at start-up.
- **"Done" is proven locally**, with the `devcontainer` CLI and in CI. The final check, a real
  GitHub Codespace, is the owner's.
