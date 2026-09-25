# Changes from the approved design

This log covers the MVP build, made while the owner was away. It records every place where the
build diverges from [`DESIGN.md`](DESIGN.md) as reviewed in PR #4, and why. Entries are
newest-first.

## Review rounds (2026-09-25)

Three Codex (gpt-6-sol) reviewers covered the backend, the feature packaging and the UI, and found
19 defects. All were fixed with red-then-green tests. A fourth Codex pass verified the fixes
independently by reverting each one: 14 were confirmed, 4 were partial, and it found 5 new small
issues. Four of the partial fixes and four of the new issues were closed in round 2.
Behaviour-visible changes:

- **Symbolic links never lead outside their folder.** Tutor refuses to adopt, seed or write
  progress through a symlinked `spec/`, `seeds/` or seed file (a dangling seed link included). It
  refuses a course whose `course.yaml`, ledger, root `README.md`, homework folders, coach or
  lexicon are symlinks leading outside the course.
- **The course checkout can't be chosen as the factory.** Neither can a folder inside it or one
  holding it. First run marks such projects "shares a folder with the course". The check is
  repeated on every load: a stored binding whose folder later leads into the course is treated as
  missing, so no coach runs and nothing is written.
- **A homework needs `README.md` and at least one `.feature` file.** `FACTORY.md` and `spec.md`
  are optional. A homework without feature files is a course load error and can never be adopted.
- **Concurrency.** Progress mutations and "find or spawn the main coach" are serialised per
  factory / homework with an in-process lock (BB runs one server process).
- **`PROGRESS.yaml` never loses what it doesn't understand.** Unknown fields survive, including
  when a homework moves into `history`. Malformed history is reported and written back verbatim.
- **Pages revalidate their data on mount.** A 3-second sharing window deliberately lets the rail,
  the page and the nav badge share one request. The reviewer's "a remount within 3 s shows cached
  data" was rejected as the intended trade-off.
- **The rail's "Start with your coach" opens the lesson.** While no factory is bound, coach
  actions lead to the welcome page. While the binding is still loading, none is offered.
- **Rule links carry the Rule in the URL** (`lesson/NNN/<feature>/<rule>`), so they survive a new
  tab or a reload.
- **Word spaces render in the fallback sans face.** Archivo's own space is very narrow in some
  renderers.
- **The start-up script checks the plugin's status, not just its install path.** A disabled
  plugin is left off; a failed one is reloaded, and the script fails if it stays down. The
  plugin copy's digest includes the built bundle, so a bb-app upgrade restages it.

## Build (2026-09-25)

Judgement calls the four builders made that change user-visible behaviour or the design's
contracts. Smaller implementation choices are in `IMPLEMENTATION.md`.

**Course content**
- **Homework 0 is a built-in course** in `server/course/builtin/`, with its own `course.yaml`,
  shown first as homework "000". It has 5 Rules and 9 Examples. It is tracked only in
  `spec/PROGRESS.yaml`, never `spec/ITERATION`. Its evidence is the student describing what they
  saw.
- **A mistake in `course.yaml` fails loudly.** A named `coach` or `lexicon` file that doesn't
  exist, or a path that leaves the course folder, stops loading with an error naming the line.
  A course without `course.yaml` falls back to the ledger table.
- **The lesson's dek skips boilerplate.** Sentences that repeat across a course's READMEs (for
  example "Read `FACTORY.md`, then…") are left out.
- **The "New since" box is generated from the data**, one line per changed feature file, instead
  of the mockup's hand-written bullets. It is omitted when everything is new.

**Coach and progress**
- **Tools act on the homework the repo says is current.** They refuse threads Tutor didn't spawn
  and threads outside the bound factory project. A thread's role (main or side) comes from its
  BB-set parent, not from metadata. Only the main thread can move the focus.
- **Adopting homeworks:** Homework 0 first; the first real homework can be adopted from Homework
  0, so the student can skip it. After that, only the homework after a Done one.
- **`tutor_complete_iteration` doesn't require every Example to pass** for a real homework, because
  coach-me decides when it's done; it notes how many are open. Homework 0 does require them.
- **Seeds are named `seeds/<slug of the seed's first heading>.md`.** coach-me hard-codes
  `seeds/tetris.md`; the generic rule gives the same name for this course.
- **File I/O uses `node:fs` on the BB server's machine**, not `bb.sdk.files`, because a course
  codespace is a single machine.
- **Opening a done homework with no coach thread spawns a "revisit" coach** that is told not to
  change the student's progress.
- **The collision guard holds a turn with `wait`** (backstop `sendAt` 60 s) while a sibling
  Tutor thread in the project is running, and releases it when that thread goes idle.

**UI**
- **Clicking a Rule in the rail opens it on the lesson page.** A "Work on this Rule next" button
  then tells the coach (decision 4's redirect), so a stray sidebar click never messages the coach.
- **Lesson page layout:** other features are listed folded above the feature in focus, so the
  lesson still ends at the Rule in focus. Without a stored focus, the first unfinished Rule is
  shown as "up next". Each Example gets its own gutter/steps/margin row in the annotated Gherkin.
- **The red margin rule runs beside the paper lesson but not beside BB's chat**, because
  `ThreadChat` centres its own column.
- **Additions beyond the mockups:** a "You finished homework N, see what's next" banner; a
  status-chip row under the dek; and a progress badge on the Course nav row
  (`experimental_sidebarAccessory`).
- **First run says "Start the course →"**, and the nothing-found state offers "Check again" and
  "use one of these projects anyway".

**Feature and packaging**
- **The tutor feature has no `installsAfter`.** The devcontainer CLI can't resolve the unpublished
  `bb` feature, so compositions use `overrideFeatureInstallOrder`. Add `installsAfter` once `bb`
  is published.
- **The Codespace entry point commits copies of `src/bb` and `src/tutor`** under
  `.devcontainer/tutor/features`. Symlinks fail ("Failed to fetch feature"). The copies are kept
  current by `sync-features.sh`, which CI checks.
- **Node comes from the `javascript-node:24` image**, not the node feature, because BB runs with a
  fixed system `PATH` that can't see nvm's node.
- **The feature seeds BB's plugin build toolchain at start**, so starting needs no network (BB
  would otherwise download about 30 MB on first start).
- **The course is registered as a BB project too**, alongside the factory.
- **The rail is selected at most once per BB state directory**, and only while BB's default list
  is active. A student who switches back is never overridden.
- **Extra feature options:** `courseRepo` (https only; empty means don't clone) and `selectRail`.
  The feature is version 0.1.0.

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
