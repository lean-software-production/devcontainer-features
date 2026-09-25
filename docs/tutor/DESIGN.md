# Tutor: a BB plugin for coached, Gherkin-driven courses

Status: **proposed**. This covers design only: there is no code yet, and a spike comes first (see
[Spike](#spike-first)). Open [`mockups.html`](mockups.html) in a browser to see the screens this
doc refers to.

## What it is

A course codespace runs its own BB (see the `bb` feature). **Tutor** adds a guided course to that
BB:

- The sidebar becomes the course rail. It shows which homework you are on, which Rule, and what
  has passed.
- Each homework gets its own coach thread in the student's *factory* project, the repo where they
  build their software factory. The coach works one Gherkin Rule at a time.
- Progress is recorded in the student's repo, so it survives the codespace and still works if
  the student drops BB and says "coach me" in any other agent harness.

The first course is
[`lean-software-production/tutorial`](https://github.com/lean-software-production/tutorial). Each
homework in `docs/iterations/NNN-*/` is a cumulative spec: `README.md`, `FACTORY.md`,
`features/*.feature`, and an optional seed `spec.md`. The engine itself is course-agnostic.

The visual language (grid-paper page, red margin rule, Spectral / Archivo / JetBrains Mono, ✓ ● ○
rail glyphs) comes from the `workbook-tutor` branch of `software-factory-tutorial`, directory
`tutorial-engine/`. That code is MIT licensed, and its CSS tokens and fonts can be lifted.

## Decisions

| # | Decision | Why |
|---|---|---|
| 1 | **Wrap the course's `coach-me.md`, don't replace it.** Its conventions stay canonical: `spec/ITERATION`, the `spec/` snapshot, and `seeds/`. | A student can leave BB at any point and carry on with plain Claude Code or Pi. |
| 2 | **Per-Example progress lives in the student's repo**, in `spec/PROGRESS.yaml`, committed with the work. | Portable and visible in git history. A non-BB coach can honour it after a small, additive change to `coach-me.md`. |
| 3 | **The "you are here" unit is the Rule.** The rail shows homework → feature → Rule, and each Rule's Examples form its checklist. | A Rule is about the size of one coaching step. |
| 4 | **The coach moves the cursor.** The plugin suggests an order (new or reworded Rules first, then file order), and the student can redirect by clicking a Rule. | Matches coach-me's "baby steps" judgement. |
| 5 | **One coach thread per homework**, plus side threads as its children. Side threads have full powers in the same working tree. | Keeps each thread's context bounded, makes the thread list read like the syllabus, and lets the student ask side questions without derailing the main thread. |
| 6 | **Faithful paper styling, scoped to the plugin's own surfaces**, light mode only. BB-drawn chat keeps BB's styling. | BB doesn't let plugins restyle its chat, and overriding its CSS would break silently on upgrades. |
| 7 | **The coach marks Examples, and evidence is required.** The command and its output, or a test name, are stored alongside. | The course has no step definitions, and each student chooses their own CLI shape, so a shared harness isn't possible yet. |
| 8 | **The student's factory project is picked or confirmed, never created by the plugin.** The `bb` feature's post-create step can register it ahead of time. | Coach-me setup mode already creates the factory repo. |
| 9 | **Engine and content are separate.** The engine is generic; **a course repo is its content package**, described by a new `course.yaml`. | Lessons ship as they are written (push to the course repo), and the engine can serve other courses. Per-lesson plugins were considered and rejected: they would only pay off for pacing, which isn't a goal. |
| 10 | **The engine lives here, in devcontainer-features**, as a `tutor` feature plus the plugin it path-installs. | The engine only makes sense on a course codespace, and pinning it to the image makes it reproducible. The cost is that engine fixes need a feature release and a codespace rebuild; content fixes don't. |
| 11 | **Instructors are out of scope for v1.** | Progress is in the students' repos, so it's readable from git. `student-tracker` integration can come later. |

UX picks from the round-2 mockups:

| Area | Choice |
|---|---|
| Sidebar | **1B**: rail plus a conversations tray |
| Lesson page | **2A**: the lesson leads the thread |
| Coach moments in the chat | **3A**: progress cards and lexicon terms |
| Example states | **6B**: annotated Gherkin |

Choice buttons (3B) were not chosen, so "jfdi" stays a phrase the student types, as in coach-me.

## Architecture

```
course codespace
├── BB (bb feature, standalone)
│   └── bb-plugin-tutor  ← path-installed by the tutor feature at image build
│         reads ──► /workspaces/tutorial        (course repo = content, `course.yaml`)
│         reads/writes ─► /workspaces/my-factory (student project: spec/ITERATION, spec/PROGRESS.yaml)
│         spawns ──► coach threads in the my-factory BB project
└── /workspaces/tutorial, /workspaces/my-factory
```

### Packaging: the `tutor` feature

- `src/tutor/` holds `devcontainer-feature.json`, `install.sh` and `plugin/` (the BB plugin
  source, pinned to the host SDK; 0.5.9 at the time of writing).
- `installsAfter: ["…/bb"]`. When the codespace starts it runs
  `bb plugin install <feature-dir>/plugin` (a path install, so nothing is fetched at runtime).
- Options:
  - `course`: path to the course checkout, default `/workspaces/tutorial`;
  - `factory`: optional path to pre-register as the student project.

### Content contract: `course.yaml` (new, in the course repo)

```yaml
# Read by bb-plugin-tutor. Everything else is discovered from the paths below.
id: software-factory
title: Build a software factory
coach: .agents/coach-me.md        # per-course coaching guidance, used by the coach
lexicon: docs/lexicon.yaml        # optional; drives ::term pop-ups
homeworks:
  - { id: "001", title: Basic unvalidated loop, set: Day 1, dir: docs/iterations/001-basic-unvalidated-loop }
  - { id: "002", title: Checking the work,      set: Day 2, dir: docs/iterations/002-checking-the-work }
  # … one entry per homework, in order
```

Each `dir` holds `README.md`, `FACTORY.md`, `features/*.feature` and an optional `spec.md`. Feature
files are parsed with `@cucumber/gherkin`. The course uses `Feature` → `Background` → `Rule` →
`Example`, plus DOT docstrings and the `@real-agent` tag, and the parser handles all of it.

The engine computes:

- **New since the previous homework:** Examples keyed by `(feature file, Rule, Example)` slugs are
  compared across homeworks, falling back to hashes of their text.
- **Carry-over:** when a student adopts homework N+1, an Example whose text hash matches one they
  have already passed keeps its `passing` status.

The engine ships its own course, **Homework 0 "Using your tutor"**. It is written in the same
format and teaches the interface by using it. For example, one Example is "When you spin off a
side thread from a Rule, then it appears under that Rule", and the coach checks it off like any
other Example.

### Student state: `spec/PROGRESS.yaml` (new, in the factory repo)

```yaml
iteration: "003"
focus: assembly-line/refuses-an-assembly-line-naming-a-machine-it-does-not-have
examples:
  assembly-line/refuses-an-assembly-line-naming-a-machine-it-does-not-have/a-misspelt-validator:
    status: not-yet            # pending | not-yet | passing | skipped
    hash: sha256:…             # of the Example's text, for carry-over
    note: Crashed in the doer loop instead of refusing when the line was read.
    at: 2026-09-25T10:12:00Z
  orchestration/a-task-is-finished-when-validation-is-satisfied/the-work-is-wrong-first-time:
    status: passing
    hash: sha256:…
    evidence: |
      $ ./factory --job t --line lines/careful.dot --agent stand-ins/never-satisfied …
      validator: NOT SATISFIED (attempt 1/3) → doer
      validator: satisfied (attempt 2/3) → plan_complete
    at: 2026-09-25T09:58:00Z
```

- Only the coach tools write this file, and it gets committed along with the coach's normal
  commits.
- The plugin re-reads it when a thread goes idle and whenever a page loads, so edits made outside
  BB show up.

### Coach threads, tools and scoping

**Threads**

- `threads.spawn` creates one main thread per homework in the factory project:
  - title `Coach · Homework 003`;
  - `pluginMetadata {course, iteration, role: "main"}`.
- Side threads are children of it (`parentThreadId`), with `role: "side"` and an optional
  `ruleKey`.
- Threads are found again with `threads.list({ originPluginId })`, so reopening a homework
  refocuses its existing thread.

**Tools and skill**

`bb.agents.configure` gives these only to threads this plugin spawned:

| Tool | Does |
|---|---|
| `tutor_status` | Current homework, focus and Example states |
| `tutor_focus_rule` | Moves the cursor |
| `tutor_mark_example` | Sets an Example's status; `evidence` is required for `passing` and a `note` for `not-yet` |
| `tutor_adopt_iteration` | Copies the homework into `spec/`, as coach-me does |
| `tutor_complete_iteration` | Sets `NNN Done` in `spec/ITERATION` |
| `tutor_side_thread` | Spawns a side thread |

Alongside the tools, a `tutor` skill explains BB-specific behaviour and tells the coach to follow
the course's `coach` file as its coaching method.

**Collision guard:** a `message.dispatch` hook queues a coach thread's turn while a sibling coach
thread in the same project is still working. Side threads share the working tree, so this stops
two turns editing it at once.

**Metadata is not trusted:** it can be written by the thread's own agent, so it's never used for
authorisation. Tools re-derive everything from the repo.

### UI surfaces

| Surface | BB API | Mockup |
|---|---|---|
| Course rail in the sidebar: days strip, progress card, current homework's Rules, conversations tray | `experimental_threadList` (a takeover; BB still draws the nav and footer) | 1B |
| Lesson page: one `ThreadChat` (`full`) whose leading content is the paper lesson (header, what's new, completed Rules collapsed, the Rule in focus as annotated Gherkin), with BB's composer docked | `navPanel` and `ThreadChat` with `leadingContent` | 2A, 6B |
| "Open as thread": the plain thread view plus a Rule tab in the right panel | `threadPanelAction` | 2C, 4 |
| Progress cards and lexicon pop-ups inside chat | `messageDirective` (`::tutor-progress`, `::term`) | 3A |
| "Continue" section on BB's home page | `homepageSection` | 5 |
| Between homeworks: summary, confetti, `FACTORY.md` diff, "Start homework N" | `navPanel` | 7 |
| First run: confirm the detected factory project, or the fallback picker | `navPanel` and a `project` setting | 8 |

Paper CSS is scoped to plugin-owned elements. In `mockups.html`, turn on **Show BB / plugin
boundaries** to see exactly which regions the plugin owns and which BB draws.

## Spike first

Each of these needs to be confirmed on SDK 0.5.9 before the plan firms up:

1. **Sidebar takeover.** How `experimental_threadList` behaves: mobile drawer, selecting and
   pinning it in Settings, and the other-threads tray (the takeover has no "render BB's list"
   fallback).
2. **Lesson page layout.** How `ThreadChat variant="full"` with `leadingContent` looks on a
   grid-paper background inside a `navPanel` page, including scroll and composer docking.
3. **Chat cards.** `messageDirective` rendering in coach replies.
4. **Scoping.** Whether `configure` hides the plugin's tools and skill from threads it didn't
   spawn.
5. **Install at image build.** Path-installing the plugin from the feature when the codespace
   starts, alongside `bb-feature-autostart`.

## Risks

- **The course is still changing fast** (renumbered on 2026-09-23). Rules are keyed on wording,
  so a reworded Rule resets its Examples to `pending`. Hash carry-over softens this.
- **Several APIs are marked experimental**: `experimental_threadList`, some sidebar hooks and
  directives. Pin the BB version in the feature, as the `bb` feature already does.
- **Engine fixes are slow to reach students**, because they need a codespace rebuild.

## Follow-ups outside this repo

These are in `lean-software-production/tutorial`, and nothing has been pushed there yet:

- Add `course.yaml`.
- Add a small `spec/PROGRESS.yaml` section to `.agents/coach-me.md`, so coaching without BB
  honours it.

## Out of scope for v1

- Instructor view and `student-tracker` integration
- Stand-in-driven automated probes for the deterministic Examples in `agent.feature`
- Choice buttons that replace the composer
- Dark mode
- Mobile polish
- Per-lesson plugins
